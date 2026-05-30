defmodule SubzeroSim.Compiler do
  @moduledoc """
  Compiles a SimSpec into a subzero-swarms configuration map.

  The compiler:
  1. Expands roles into individual agents (e.g., :trader with count=5 → :trader_1..5)
  2. Passes through user-defined objects
  3. Injects Tick and Metrics objects with appropriate configs
  4. Optionally injects Gateway object for child simulations
  5. Generates the topology with all connections expanded
  """

  alias SubzeroSim.Spec.{SimSpec, RoleSpec, Connection}

  @doc """
  Compiles a SimSpec into a subzero-swarms config map.

  Options for child simulations:
    - `:parent` - Parent process PID
    - `:inject_to` - Agent role to receive initial_task
    - `:collect_from` - Agent role to collect final_result from
    - `:initial_task` - Task data to inject

  Returns `{:ok, config}` on success.
  """
  @spec compile(SimSpec.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile(%SimSpec{} = spec, opts \\ []) do
    agent_names = SimSpec.agent_names(spec)
    role_name_map = build_role_name_map(spec.roles)

    agents = compile_agents(spec.roles, spec.source_dir)
    user_objects = compile_user_objects(spec.objects, spec.name)
    tick_object = compile_tick_object(spec, agent_names, opts)
    metrics_object = compile_metrics_object(spec, agent_names)

    # Optionally inject Gateway for child simulations
    gateway_object = maybe_compile_gateway_object(spec, agent_names, opts)

    objects =
      if gateway_object do
        user_objects ++ [tick_object, metrics_object, gateway_object]
      else
        user_objects ++ [tick_object, metrics_object]
      end

    # Get user object names for topology
    user_object_names = Enum.map(spec.objects, & &1.name)

    # Merge tick opts into compile opts for topology generation
    topology_opts = Keyword.merge(opts, Map.to_list(spec.tick_config.opts))

    topology = compile_topology(spec.connections, role_name_map, agent_names, spec.tick_config.mode, topology_opts, user_object_names)

    config = %{
      name: spec.name,
      agents: agents,
      objects: objects,
      topology: topology
    }

    # Add skills_base_dir if source_dir is set
    config =
      if spec.source_dir do
        Map.put(config, :skills_base_dir, spec.source_dir)
      else
        config
      end

    {:ok, config}
  end

  # Build a map from role name to list of expanded agent names
  defp build_role_name_map(roles) do
    Enum.reduce(roles, %{}, fn role, acc ->
      names = RoleSpec.expand_names(role)
      Map.put(acc, role.name, names)
    end)
  end

  defp compile_agents(roles, source_dir) do
    Enum.flat_map(roles, fn role ->
      names = RoleSpec.expand_names(role)

      Enum.map(names, fn name ->
        # For counted roles with workspace config, append agent name for isolation
        # Unless shared_workspace: true (e.g., pop_gen agents all write to same dir)
        config = if role.count > 1 && role.config[:workspace] && !role.config[:shared_workspace] do
          Map.update!(role.config, :workspace, fn ws ->
            Path.join(ws, to_string(name))
          end)
        else
          role.config
        end

        agent = %{
          name: name,
          backend: role.backend
        }

        agent
        |> maybe_add(:presets, role.preset, fn p -> [p] end)
        |> maybe_add(:skills, role.skill, fn s -> [resolve_skill_path(s, source_dir)] end)
        |> maybe_add(:model, role.model)
        |> maybe_add(:endpoint, role.endpoint)
        |> maybe_add(:config, config, fn c -> if c == %{}, do: nil, else: c end)
      end)
    end)
  end

  # Resolve skill path relative to source_dir
  defp resolve_skill_path(skill_path, nil), do: skill_path

  defp resolve_skill_path(skill_path, source_dir) do
    if Path.type(skill_path) == :absolute do
      skill_path
    else
      Path.join(source_dir, skill_path)
    end
  end

  defp compile_user_objects(objects, sim_name) do
    Enum.map(objects, fn obj ->
      # Add swarm_name to config so objects can send messages via Router
      config = Map.put(obj.config, :swarm_name, sim_name)

      %{
        name: obj.name,
        handler: obj.handler,
        config: config
      }
    end)
  end

  defp compile_tick_object(spec, agent_names, opts) do
    # Check if this is a child simulation (has gateway)
    has_gateway = Keyword.get(opts, :parent) != nil

    %{
      name: :tick,
      handler: SubzeroSim.Objects.Tick,
      config: %{
        sim_name: spec.name,
        mode: spec.tick_config.mode,
        opts: spec.tick_config.opts,
        start_trigger: spec.start_trigger,
        agent_names: agent_names,
        max_steps: spec.steps,
        has_gateway: has_gateway
      }
    }
  end

  defp maybe_compile_gateway_object(spec, agent_names, opts) do
    parent_pid = Keyword.get(opts, :parent)

    if parent_pid do
      inject_to = Keyword.get(opts, :inject_to)
      collect_from = Keyword.get(opts, :collect_from)
      initial_task = Keyword.get(opts, :initial_task)

      # Resolve role names to actual agent names if needed
      resolved_inject_to = resolve_agent_name(inject_to, agent_names)
      resolved_collect_from = resolve_agent_name(collect_from, agent_names)

      %{
        name: :gateway,
        handler: SubzeroSim.Objects.Gateway,
        config: %{
          sim_name: spec.name,
          parent_pid: parent_pid,
          inject_to: resolved_inject_to,
          collect_from: resolved_collect_from,
          initial_task: initial_task
        }
      }
    else
      nil
    end
  end

  # Resolve a role name to the first matching agent name
  defp resolve_agent_name(nil, _agent_names), do: nil

  defp resolve_agent_name(role, agent_names) do
    role_str = Atom.to_string(role)

    # First check for exact match
    if role in agent_names do
      role
    else
      # Look for role_1, role_2, etc.
      Enum.find(agent_names, role, fn name ->
        name_str = Atom.to_string(name)
        String.starts_with?(name_str, role_str <> "_")
      end)
    end
  end

  defp compile_metrics_object(spec, agent_names) do
    # Pass tick config options for metrics timeouts and mode
    tick_opts = if spec.tick_config do
      %{}
      |> maybe_put_opt(:tick_mode, spec.tick_config.mode)
      |> maybe_put_opt(:state_report_timeout, spec.tick_config.opts[:retry_timeout])
      |> maybe_put_opt(:max_retries, spec.tick_config.opts[:max_retries])
    else
      %{}
    end

    %{
      name: :metrics,
      handler: SubzeroSim.Objects.Metrics,
      config: Map.merge(%{
        sim_name: spec.name,
        agent_names: agent_names,
        measures: spec.measures,
        halt_conditions: spec.halt_conditions
      }, tick_opts)
    }
  end

  defp maybe_put_opt(map, _key, nil), do: map
  defp maybe_put_opt(map, key, value), do: Map.put(map, key, value)

  defp compile_topology(connections, role_name_map, agent_names, tick_mode, opts, object_names) do
    # Expand user-defined connections
    user_edges =
      Enum.flat_map(connections, fn conn ->
        expand_connection(conn, role_name_map)
      end)

    # Add tick → all agents edges
    tick_to_agents =
      Enum.map(agent_names, fn name ->
        {:tick, name}
      end)

    # Add all agents → metrics edges
    agents_to_metrics =
      Enum.map(agent_names, fn name ->
        {name, :metrics}
      end)

    # Add metrics → all agents edges (for broadcasting new_step/your_turn)
    metrics_to_agents =
      Enum.map(agent_names, fn name ->
        {:metrics, name}
      end)

    # Add tick ↔ metrics coordination edges
    tick_metrics = [
      {:tick, :metrics},
      {:metrics, :tick}
    ]

    # For turn_based and output_count modes, agents need to send to tick
    # - turn_based: agents send turn_complete to tick
    # - output_count: agents send output_reported to tick
    agents_to_tick =
      if tick_mode in [:turn_based, :output_count] do
        Enum.map(agent_names, fn name ->
          {name, :tick}
        end)
      else
        []
      end

    # Add gateway edges if this is a child simulation
    gateway_edges = compile_gateway_edges(agent_names, opts)

    # Allow user-defined objects to send state_reports to metrics
    objects_to_metrics =
      Enum.map(object_names, fn name ->
        {name, :metrics}
      end)

    # For wait_for_objects mode, user objects need to send to tick
    objects_to_tick =
      if Keyword.get(opts, :wait_for_objects) do
        Enum.map(object_names, fn name ->
          {name, :tick}
        end)
      else
        []
      end

    # For pipeline mode, coordinator object needs to send advance_step to tick
    coordinator_to_tick =
      case Keyword.get(opts, :coordinator) do
        coord when is_atom(coord) and not is_nil(coord) -> [{coord, :tick}]
        _ -> []
      end

    user_edges ++
      tick_to_agents ++
      agents_to_metrics ++
      metrics_to_agents ++
      tick_metrics ++
      agents_to_tick ++
      gateway_edges ++
      objects_to_metrics ++
      objects_to_tick ++
      coordinator_to_tick
  end

  defp compile_gateway_edges(agent_names, opts) do
    parent_pid = Keyword.get(opts, :parent)

    if parent_pid do
      inject_to = Keyword.get(opts, :inject_to)
      collect_from = Keyword.get(opts, :collect_from)

      # tick → gateway (for simulation_started)
      tick_to_gateway = [{:tick, :gateway}]

      # gateway → inject_to agent (for initial_task)
      gateway_to_inject =
        if inject_to do
          resolved = resolve_agent_name(inject_to, agent_names)
          [{:gateway, resolved}]
        else
          []
        end

      # collect_from agent → gateway (for final_result)
      collect_to_gateway =
        if collect_from do
          # Connect all agents matching the collect_from role
          agent_names
          |> Enum.filter(fn name ->
            name_str = Atom.to_string(name)
            collect_str = Atom.to_string(collect_from)
            name == collect_from or String.starts_with?(name_str, collect_str <> "_")
          end)
          |> Enum.map(fn name -> {name, :gateway} end)
        else
          # If no collect_from specified, all agents can send to gateway
          Enum.map(agent_names, fn name -> {name, :gateway} end)
        end

      tick_to_gateway ++ gateway_to_inject ++ collect_to_gateway
    else
      []
    end
  end

  defp expand_connection(%Connection{} = conn, role_name_map) do
    from_names = expand_node(conn.from, role_name_map)
    to_names = expand_node(conn.to, role_name_map)

    edges =
      for from <- from_names, to <- to_names do
        {from, to}
      end

    if conn.bidirectional do
      reverse_edges =
        for from <- from_names, to <- to_names do
          {to, from}
        end

      edges ++ reverse_edges
    else
      edges
    end
  end

  defp expand_node(name, role_name_map) do
    case Map.get(role_name_map, name) do
      nil -> [name]
      names -> names
    end
  end

  defp maybe_add(map, _key, nil, _transform), do: map

  defp maybe_add(map, key, value, transform) do
    case transform.(value) do
      nil -> map
      v -> Map.put(map, key, v)
    end
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
