defmodule SubzeroSim.DSL do
  @moduledoc """
  Domain-Specific Language for defining simulations.

  Provides macros for building simulation specifications in .sim files.

  ## Example

      use SubzeroSim.DSL

      simulation "market_sim" do
        tick :state_reports
        start :immediate
        steps 100

        agent :trader, count: 5, backend: :anthropic do
          skill "trader.md"
          config wealth: 1000, inventory: 0
        end

        agent :market, backend: :anthropic do
          skill "market.md"
        end

        object :orderbook, handler: MyApp.Orderbook

        connect :trader, :market, bidirectional: true
        connect :trader, :orderbook

        measure :total_wealth, fn states ->
          states |> Map.values() |> Enum.map(& &1["wealth"]) |> Enum.sum()
        end

        halt after: 100
        halt when: fn metrics -> metrics[:total_wealth] > 1_000_000 end
      end
  """

  alias SubzeroSim.Spec.{
    SimSpec,
    TickConfig,
    RoleSpec,
    ObjectSpec,
    Connection,
    MeasureSpec,
    HaltCondition
  }

  defmacro __using__(_opts) do
    quote do
      import SubzeroSim.DSL
    end
  end

  @doc """
  Defines a simulation with the given name.
  """
  defmacro simulation(name, do: block) do
    quote do
      var!(sim_acc) = SimSpec.new(unquote(name))
      unquote(block)
      var!(sim_acc)
    end
  end

  @doc """
  Sets the tick mode for the simulation.

  ## Modes

    - `:state_reports` (default) - Step advances when all agents have reported state
    - `:turn_based` - Explicit your_turn/turn_complete coordination
    - `:time_interval` - Step advances every N seconds (requires `every: seconds`)
    - `:output_count` - Step advances after N LLM outputs (requires `every: count`)

  ## Options

    - `:parallel` - For turn_based mode, all agents act simultaneously
    - `:every` - For time_interval/output_count modes, the interval value
    - `:wait_for_objects` - For turn_based mode, wait for objects to signal ready
      before advancing. Objects send `{"action": "object_busy"}` when starting
      long-running work and `{"action": "object_ready"}` when done.
  """
  defmacro tick(mode, opts \\ []) do
    quote do
      tick_config = TickConfig.new(unquote(mode), unquote(opts))
      var!(sim_acc) = %{var!(sim_acc) | tick_config: tick_config}
    end
  end

  @doc """
  Sets the start trigger for the simulation.

  ## Triggers

    - `:immediate` (default) - Start as soon as simulation launches
    - `:on_ready` - Wait for all agents to signal ready
    - `{:delayed, N}` - Start after N seconds
    - `:manual` - Wait for explicit start command
  """
  defmacro start(trigger) do
    quote do
      var!(sim_acc) = %{var!(sim_acc) | start_trigger: unquote(trigger)}
    end
  end

  @doc """
  Sets the maximum number of steps for the simulation.
  """
  defmacro steps(count) do
    quote do
      var!(sim_acc) = %{var!(sim_acc) | steps: unquote(count)}
    end
  end

  @doc """
  Defines an agent role.

  ## Options

    - `:count` - Number of agents to create from this role (default: 1)
    - `:backend` - LLM backend (default: :anthropic)
    - `:preset` - Preset name to use
    - `:model` - Model to use
    - `:endpoint` - Custom endpoint

  ## Block

  Inside the block, you can use:
    - `skill "path.md"` - Set the skill file
    - `config key: value` - Set config values

  ## Examples

      # Simple agent
      agent :worker

      # Agent with options
      agent :trader, count: 5, backend: :openai

      # Agent with block
      agent :trader, count: 5 do
        skill "trader.md"
        config wealth: 1000
      end
  """
  defmacro agent(name, opts_or_block \\ [])

  defmacro agent(name, do: block) do
    quote do
      var!(role_acc) = RoleSpec.new(unquote(name), [])
      unquote(block)
      var!(sim_acc) = %{var!(sim_acc) | roles: var!(sim_acc).roles ++ [var!(role_acc)]}
    end
  end

  defmacro agent(name, opts) do
    quote do
      role = RoleSpec.new(unquote(name), unquote(opts))
      var!(sim_acc) = %{var!(sim_acc) | roles: var!(sim_acc).roles ++ [role]}
    end
  end

  @doc """
  Defines an agent role with options and a block.
  """
  defmacro agent(name, opts, do: block) do
    quote do
      var!(role_acc) = RoleSpec.new(unquote(name), unquote(opts))
      unquote(block)
      var!(sim_acc) = %{var!(sim_acc) | roles: var!(sim_acc).roles ++ [var!(role_acc)]}
    end
  end

  @doc """
  Sets the skill file for the current agent role.
  """
  defmacro skill(path) do
    quote do
      var!(role_acc) = %{var!(role_acc) | skill: unquote(path)}
    end
  end

  @doc """
  Sets config values for the current agent role.
  """
  defmacro config(opts) do
    quote do
      existing_config = var!(role_acc).config || %{}
      new_config = Map.merge(existing_config, Map.new(unquote(opts)))
      var!(role_acc) = %{var!(role_acc) | config: new_config}
    end
  end

  @doc """
  Defines a user object.

  ## Options

    - `:handler` - The ObjectHandler module (required)
    - `:config` - Configuration map for the handler
  """
  defmacro object(name, opts) do
    quote do
      handler = Keyword.fetch!(unquote(opts), :handler)
      config = Keyword.get(unquote(opts), :config, %{})
      obj = ObjectSpec.new(unquote(name), handler, config: config)
      var!(sim_acc) = %{var!(sim_acc) | objects: var!(sim_acc).objects ++ [obj]}
    end
  end

  @doc """
  Defines a connection between nodes.

  ## Options

    - `:bidirectional` - Create edges in both directions (default: false)
  """
  defmacro connect(from, to, opts \\ []) do
    quote do
      conn = Connection.new(unquote(from), unquote(to), unquote(opts))
      var!(sim_acc) = %{var!(sim_acc) | connections: var!(sim_acc).connections ++ [conn]}
    end
  end

  @doc """
  Defines a metric to be measured.

  ## Options

    - `:every` - Compute every N steps (default: 1)
  """
  defmacro measure(name, fun) do
    quote do
      m = MeasureSpec.new(unquote(name), unquote(fun))
      var!(sim_acc) = %{var!(sim_acc) | measures: var!(sim_acc).measures ++ [m]}
    end
  end

  defmacro measure(name, opts, fun) do
    quote do
      m = MeasureSpec.new(unquote(name), unquote(fun), unquote(opts))
      var!(sim_acc) = %{var!(sim_acc) | measures: var!(sim_acc).measures ++ [m]}
    end
  end

  @doc """
  Defines a halt condition.

  ## Options

  Basic conditions:
    - `after: N` - Halt after N steps
    - `when: fn` - Halt when predicate on current metrics returns true

  History-aware conditions:
    - `when_history: fn` - Halt when predicate on `{metrics, history}` returns true.
      History is a map of metric_name => [{step, value}, ...].

  Convergence conditions:
    - `converged: [metric: :name, threshold: N]` - Halt when metric varies by less
      than threshold over a window of steps. Options: `:window` (default: 10)
    - `plateaued: [metric: :name, threshold: N]` - Halt when metric's average
      change per step falls below threshold. Options: `:window` (default: 10)

  ## Examples

      halt after: 100
      halt when: fn metrics -> metrics[:done] end
      halt when_history: fn {_metrics, history} ->
        case history[:loss] do
          series when length(series) > 10 ->
            recent = Enum.take(series, -10) |> Enum.map(&elem(&1, 1))
            Enum.max(recent) - Enum.min(recent) < 0.001
          _ -> false
        end
      end
      halt converged: [metric: :wealth, threshold: 100, window: 10]
      halt plateaued: [metric: :gini, threshold: 0.01]
  """
  defmacro halt(opts) do
    quote do
      condition =
        cond do
          Keyword.has_key?(unquote(opts), :after) ->
            HaltCondition.after_steps(Keyword.fetch!(unquote(opts), :after))

          Keyword.has_key?(unquote(opts), :when) ->
            HaltCondition.when_predicate(Keyword.fetch!(unquote(opts), :when))

          Keyword.has_key?(unquote(opts), :when_history) ->
            HaltCondition.when_history(Keyword.fetch!(unquote(opts), :when_history))

          Keyword.has_key?(unquote(opts), :converged) ->
            conv_opts = Keyword.fetch!(unquote(opts), :converged)
            metric = Keyword.fetch!(conv_opts, :metric)
            HaltCondition.metric_converged(metric, conv_opts)

          Keyword.has_key?(unquote(opts), :plateaued) ->
            plat_opts = Keyword.fetch!(unquote(opts), :plateaued)
            metric = Keyword.fetch!(plat_opts, :metric)
            HaltCondition.metric_plateaued(metric, plat_opts)

          true ->
            raise ArgumentError,
                  "halt requires one of: :after, :when, :when_history, :converged, :plateaued"
        end

      var!(sim_acc) = %{
        var!(sim_acc)
        | halt_conditions: var!(sim_acc).halt_conditions ++ [condition]
      }
    end
  end
end
