defmodule SubzeroSim.Variant do
  @moduledoc """
  Utilities for creating variants of simulation specifications.

  Provides functions to modify SimSpec structs for creating simulation variants,
  useful for parameter sweeps, A/B testing, and batch experiments.

  ## Examples

      spec
      |> Variant.set_agent_count(:trader, 5)
      |> Variant.set_model(:trader, "anthropic/claude-haiku")
      |> Variant.update_config(:trader, %{risk_tolerance: 0.8})
      |> Variant.add_connection(:trader, :market)
      |> Variant.set_name("variant_001")

      # Generate N variants
      Variant.generate(spec, 10, fn spec, i ->
        Variant.set_agent_count(spec, :worker, i + 1)
      end)
  """

  alias SubzeroSim.Spec.{SimSpec, RoleSpec, Connection}

  @doc """
  Sets a new name for the simulation.
  """
  @spec set_name(SimSpec.t(), String.t()) :: SimSpec.t()
  def set_name(%SimSpec{} = spec, name) when is_binary(name) do
    %{spec | name: name}
  end

  @doc """
  Sets the agent count for a role.
  """
  @spec set_agent_count(SimSpec.t(), atom(), pos_integer()) :: SimSpec.t()
  def set_agent_count(%SimSpec{} = spec, role_name, count)
      when is_atom(role_name) and is_integer(count) and count > 0 do
    roles =
      Enum.map(spec.roles, fn role ->
        if role.name == role_name do
          %{role | count: count}
        else
          role
        end
      end)

    %{spec | roles: roles}
  end

  @doc """
  Sets the model for a role.
  """
  @spec set_model(SimSpec.t(), atom(), String.t()) :: SimSpec.t()
  def set_model(%SimSpec{} = spec, role_name, model)
      when is_atom(role_name) and is_binary(model) do
    roles =
      Enum.map(spec.roles, fn role ->
        if role.name == role_name do
          %{role | model: model}
        else
          role
        end
      end)

    %{spec | roles: roles}
  end

  @doc """
  Sets the backend for a role.
  """
  @spec set_backend(SimSpec.t(), atom(), atom()) :: SimSpec.t()
  def set_backend(%SimSpec{} = spec, role_name, backend)
      when is_atom(role_name) and is_atom(backend) do
    roles =
      Enum.map(spec.roles, fn role ->
        if role.name == role_name do
          %{role | backend: backend}
        else
          role
        end
      end)

    %{spec | roles: roles}
  end

  @doc """
  Updates the config for a role by merging new values.
  """
  @spec update_config(SimSpec.t(), atom(), map()) :: SimSpec.t()
  def update_config(%SimSpec{} = spec, role_name, config_updates)
      when is_atom(role_name) and is_map(config_updates) do
    roles =
      Enum.map(spec.roles, fn role ->
        if role.name == role_name do
          current_config = role.config || %{}
          %{role | config: Map.merge(current_config, config_updates)}
        else
          role
        end
      end)

    %{spec | roles: roles}
  end

  @doc """
  Sets the entire config for a role (replaces existing).
  """
  @spec set_config(SimSpec.t(), atom(), map()) :: SimSpec.t()
  def set_config(%SimSpec{} = spec, role_name, config)
      when is_atom(role_name) and is_map(config) do
    roles =
      Enum.map(spec.roles, fn role ->
        if role.name == role_name do
          %{role | config: config}
        else
          role
        end
      end)

    %{spec | roles: roles}
  end

  @doc """
  Sets the skill file for a role.
  """
  @spec set_skill(SimSpec.t(), atom(), String.t()) :: SimSpec.t()
  def set_skill(%SimSpec{} = spec, role_name, skill_path)
      when is_atom(role_name) and is_binary(skill_path) do
    roles =
      Enum.map(spec.roles, fn role ->
        if role.name == role_name do
          %{role | skill: skill_path}
        else
          role
        end
      end)

    %{spec | roles: roles}
  end

  @doc """
  Adds a connection between two nodes (roles or objects).
  """
  @spec add_connection(SimSpec.t(), atom(), atom(), keyword()) :: SimSpec.t()
  def add_connection(%SimSpec{} = spec, from, to, opts \\ [])
      when is_atom(from) and is_atom(to) do
    bidirectional = Keyword.get(opts, :bidirectional, false)

    new_conn = %Connection{
      from: from,
      to: to,
      bidirectional: bidirectional
    }

    %{spec | connections: spec.connections ++ [new_conn]}
  end

  @doc """
  Removes a connection between two nodes.
  """
  @spec remove_connection(SimSpec.t(), atom(), atom()) :: SimSpec.t()
  def remove_connection(%SimSpec{} = spec, from, to)
      when is_atom(from) and is_atom(to) do
    connections =
      Enum.reject(spec.connections, fn conn ->
        (conn.from == from and conn.to == to) or
          (conn.bidirectional and conn.from == to and conn.to == from)
      end)

    %{spec | connections: connections}
  end

  @doc """
  Sets the maximum number of steps.
  """
  @spec set_steps(SimSpec.t(), pos_integer() | nil) :: SimSpec.t()
  def set_steps(%SimSpec{} = spec, steps) when is_nil(steps) or (is_integer(steps) and steps > 0) do
    %{spec | steps: steps}
  end

  @doc """
  Sets the tick mode.
  """
  @spec set_tick_mode(SimSpec.t(), atom(), map()) :: SimSpec.t()
  def set_tick_mode(%SimSpec{} = spec, mode, opts \\ %{}) when is_atom(mode) do
    tick_config = %{spec.tick_config | mode: mode, opts: opts}
    %{spec | tick_config: tick_config}
  end

  @doc """
  Adds a new role to the simulation.
  """
  @spec add_role(SimSpec.t(), atom(), keyword()) :: SimSpec.t()
  def add_role(%SimSpec{} = spec, role_name, opts \\ []) when is_atom(role_name) do
    role = %RoleSpec{
      name: role_name,
      count: Keyword.get(opts, :count, 1),
      backend: Keyword.get(opts, :backend, :bwrap),
      model: Keyword.get(opts, :model),
      skill: Keyword.get(opts, :skill),
      preset: Keyword.get(opts, :preset),
      endpoint: Keyword.get(opts, :endpoint),
      config: Keyword.get(opts, :config, %{})
    }

    %{spec | roles: spec.roles ++ [role]}
  end

  @doc """
  Removes a role from the simulation.
  """
  @spec remove_role(SimSpec.t(), atom()) :: SimSpec.t()
  def remove_role(%SimSpec{} = spec, role_name) when is_atom(role_name) do
    roles = Enum.reject(spec.roles, &(&1.name == role_name))

    # Also remove connections involving this role
    connections =
      Enum.reject(spec.connections, fn conn ->
        conn.from == role_name or conn.to == role_name
      end)

    %{spec | roles: roles, connections: connections}
  end

  @doc """
  Generates N variants of a spec using a generator function.

  The generator function receives the base spec and the index (0-based),
  and should return a modified spec.

  ## Example

      Variant.generate(spec, 5, fn spec, i ->
        spec
        |> Variant.set_agent_count(:worker, i + 1)
        |> Variant.set_name("variant_\#{i + 1}")
      end)
  """
  @spec generate(SimSpec.t(), pos_integer(), (SimSpec.t(), non_neg_integer() -> SimSpec.t())) ::
          [SimSpec.t()]
  def generate(%SimSpec{} = base_spec, count, generator_fn)
      when is_integer(count) and count > 0 and is_function(generator_fn, 2) do
    for i <- 0..(count - 1) do
      generator_fn.(base_spec, i)
    end
  end

  @doc """
  Creates a deep copy of a spec with a new name.
  """
  @spec clone(SimSpec.t(), String.t()) :: SimSpec.t()
  def clone(%SimSpec{} = spec, new_name) when is_binary(new_name) do
    %{spec | name: new_name}
  end

  @doc """
  Gets a role from the spec by name.
  """
  @spec get_role(SimSpec.t(), atom()) :: RoleSpec.t() | nil
  def get_role(%SimSpec{} = spec, role_name) when is_atom(role_name) do
    Enum.find(spec.roles, &(&1.name == role_name))
  end

  @doc """
  Lists all role names in the spec.
  """
  @spec role_names(SimSpec.t()) :: [atom()]
  def role_names(%SimSpec{} = spec) do
    Enum.map(spec.roles, & &1.name)
  end
end
