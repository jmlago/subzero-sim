defmodule SubzeroSim.Runner do
  @moduledoc """
  Runner for starting and managing simulations.

  Provides functions to:
  - Start simulations from specs
  - Start child simulations with parent communication
  - Wait for completion
  - Stream progress updates
  - Export metrics
  """

  require Logger

  alias SubzeroSim.{Compiler, Validator, ChildHandle}
  alias SubzeroSim.Spec.SimSpec
  alias SubzeroSim.Store.{RuntimeStore, MetricsStore, ResultStore}
  alias SubzeroclawSwarm.SwarmManager

  @doc """
  Starts a simulation from a SimSpec.

  Options:
    - `:steps` - Override max steps
    - `:parallel` - Override turn_based parallel mode

  Returns `{:ok, swarm_name}` on success.
  """
  @spec start(SimSpec.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def start(%SimSpec{} = spec, opts \\ []) do
    spec = apply_overrides(spec, opts)

    with :ok <- Validator.validate(spec),
         {:ok, config} <- Compiler.compile(spec) do
      Logger.info("[Runner] Starting simulation: #{spec.name}")

      # Pre-initialize RuntimeStore so CLI can track status immediately
      # This will be overwritten by Tick.init, but prevents stale data from showing
      RuntimeStore.init_simulation(spec.name,
        agent_names: SimSpec.agent_names(spec),
        max_steps: spec.steps,
        mode: spec.tick_config.mode,
        opts: spec.tick_config.opts
      )

      SwarmManager.start_from_config(config)
    end
  end

  @doc """
  Starts a child simulation with parent-child communication.

  This injects a Gateway object that:
  1. Sends initial_task to the inject_to agent when simulation starts
  2. Collects final_result from the collect_from agent
  3. Notifies the parent process when result is received

  Options:
    - `:parent` - Parent process PID (default: self())
    - `:initial_task` - Task data to inject to the child
    - `:inject_to` - Agent role to receive the initial task
    - `:collect_from` - Agent role to collect final_result from
    - `:steps` - Override max steps
    - `:parallel` - Override turn_based parallel mode

  Returns `{:ok, %ChildHandle{}}` on success.

  ## Example

      {:ok, child} = Runner.start_child(spec,
        parent: self(),
        initial_task: %{task: "do_work"},
        inject_to: :coordinator,
        collect_from: :coordinator
      )

      {:ok, info} = Runner.wait_for_completion(child.name)
      # info.gateway_result contains the final_result data
  """
  @spec start_child(SimSpec.t(), keyword()) :: {:ok, ChildHandle.t()} | {:error, term()}
  def start_child(%SimSpec{} = spec, opts \\ []) do
    parent_pid = Keyword.get(opts, :parent, self())
    inject_to = Keyword.get(opts, :inject_to)
    collect_from = Keyword.get(opts, :collect_from)
    initial_task = Keyword.get(opts, :initial_task)

    spec = apply_overrides(spec, opts)

    # Compile with gateway injection options
    compile_opts = [
      parent: parent_pid,
      inject_to: inject_to,
      collect_from: collect_from,
      initial_task: initial_task
    ]

    with :ok <- Validator.validate(spec),
         {:ok, config} <- Compiler.compile(spec, compile_opts) do
      Logger.info("[Runner] Starting child simulation: #{spec.name}")

      # Pre-initialize RuntimeStore
      RuntimeStore.init_simulation(spec.name,
        agent_names: SimSpec.agent_names(spec),
        max_steps: spec.steps,
        mode: spec.tick_config.mode,
        opts: spec.tick_config.opts
      )

      case SwarmManager.start_from_config(config) do
        {:ok, swarm_name} ->
          handle =
            ChildHandle.new(swarm_name, parent_pid,
              inject_to: inject_to,
              collect_from: collect_from,
              initial_task: initial_task
            )

          {:ok, handle}

        error ->
          error
      end
    end
  end

  @doc """
  Waits for a simulation to complete.

  Options:
    - `:timeout` - Max wait time in milliseconds (default: :infinity)
    - `:poll_interval` - How often to check status in ms (default: 100)

  Returns `{:ok, info}` with final status, or `{:error, :timeout}`.
  """
  @spec wait_for_completion(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def wait_for_completion(swarm_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    poll_interval = Keyword.get(opts, :poll_interval, 100)

    deadline =
      case timeout do
        :infinity -> :infinity
        ms -> System.monotonic_time(:millisecond) + ms
      end

    do_wait(swarm_name, poll_interval, deadline)
  end

  defp do_wait(swarm_name, poll_interval, deadline) do
    if RuntimeStore.complete?(swarm_name) do
      {:ok, get_completion_info(swarm_name)}
    else
      now = System.monotonic_time(:millisecond)

      if deadline != :infinity and now >= deadline do
        {:error, :timeout}
      else
        Process.sleep(poll_interval)
        do_wait(swarm_name, poll_interval, deadline)
      end
    end
  end

  @doc """
  Streams progress updates to the console.

  Prints step updates as they occur until the simulation completes.
  """
  @spec stream_progress(String.t(), keyword()) :: :ok
  def stream_progress(swarm_name, opts \\ []) do
    poll_interval = Keyword.get(opts, :poll_interval, 500)
    last_step = 0

    do_stream(swarm_name, poll_interval, last_step)
  end

  defp do_stream(swarm_name, poll_interval, last_step) do
    case RuntimeStore.get_info(swarm_name) do
      nil ->
        IO.puts("Simulation not found: #{swarm_name}")
        :ok

      %{status: status, step: step} when status in [:halted, :completed] ->
        if step != last_step do
          IO.puts("Step #{step}")
        end

        IO.puts("Simulation #{status}: #{RuntimeStore.get_halt_reason(swarm_name) || "completed"}")
        :ok

      %{step: step} ->
        if step != last_step do
          IO.puts("Step #{step}")
        end

        Process.sleep(poll_interval)
        do_stream(swarm_name, poll_interval, step)
    end
  end

  @doc """
  Gets completion info for a finished simulation.

  For child simulations, also includes gateway_result if available.
  """
  @spec get_completion_info(String.t()) :: map()
  def get_completion_info(swarm_name) do
    runtime = RuntimeStore.get_info(swarm_name) || %{}
    metrics = MetricsStore.get_current(swarm_name)
    gateway_result = ResultStore.get(swarm_name)

    info = %{
      name: swarm_name,
      status: runtime[:status],
      final_step: runtime[:step],
      halt_reason: runtime[:halt_reason],
      started_at: runtime[:started_at],
      metrics: metrics
    }

    if gateway_result do
      Map.put(info, :gateway_result, gateway_result)
    else
      info
    end
  end

  @doc """
  Exports metrics to a file.

  Supported formats:
    - `:json` - JSON format
    - `:csv` - CSV format (one file per metric)
  """
  @spec export_metrics(String.t(), String.t(), atom()) :: :ok | {:error, term()}
  def export_metrics(swarm_name, path, format \\ :json) do
    metrics = MetricsStore.export(swarm_name)

    case format do
      :json ->
        json = Jason.encode!(metrics, pretty: true)
        File.write(path, json)

      :csv ->
        export_metrics_csv(metrics, path)

      _ ->
        {:error, "Unsupported format: #{format}"}
    end
  end

  defp export_metrics_csv(metrics, base_path) do
    dir = Path.dirname(base_path)
    basename = Path.basename(base_path, Path.extname(base_path))

    Enum.each(metrics, fn {metric_name, series} ->
      path = Path.join(dir, "#{basename}_#{metric_name}.csv")
      csv = ["step,value" | Enum.map(series, fn %{step: s, value: v} -> "#{s},#{v}" end)]
      File.write!(path, Enum.join(csv, "\n"))
    end)

    :ok
  end

  @doc """
  Stops a running simulation.
  """
  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(swarm_name) do
    SwarmManager.stop(swarm_name)
    RuntimeStore.set_status(swarm_name, :halted)
    RuntimeStore.set_halt_reason(swarm_name, "stopped_by_user")
    :ok
  end

  @doc """
  Runs a simulation to completion and returns metrics.

  Starts the simulation, waits for it to complete (or timeout),
  collects final metrics, and cleans up. Useful for running child
  simulations programmatically.

  ## Options

    * `:steps` - Override max steps (default: spec's steps value)
    * `:timeout` - Max wait time in ms (default: 300_000)

  ## Returns

    * `{:ok, %{status: atom, final_step: int, metrics: map}}` on success
    * `{:error, reason}` on failure
  """
  @spec run_and_collect(SimSpec.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_and_collect(%SimSpec{} = spec, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 300_000)
    steps = Keyword.get(opts, :steps)

    spec = if steps, do: %{spec | steps: steps}, else: spec

    case start(spec) do
      {:ok, swarm_name} ->
        result = wait_for_completion(swarm_name, timeout: timeout)

        # Collect metrics before cleanup
        metrics = MetricsStore.get_current(swarm_name)

        # Clean up
        SwarmManager.stop(swarm_name)

        case result do
          {:ok, info} -> {:ok, Map.put(info, :metrics, metrics || %{})}
          {:error, :timeout} -> {:ok, %{status: :timeout, metrics: metrics || %{}}}
          error -> error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Pauses a running simulation.

  The simulation will stop advancing steps but remain in memory.
  Use `resume/1` to continue.

  Uses DETS-based IPC to communicate with the Tick object in the
  running simulation process.
  """
  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(swarm_name) do
    case RuntimeStore.get_status(swarm_name) do
      :running ->
        # Request pause via DETS IPC - Tick will poll and act on this
        RuntimeStore.request_pause(swarm_name)
        :ok

      :paused ->
        {:error, :already_paused}

      status when status in [:halted, :completed] ->
        {:error, :simulation_not_running}

      nil ->
        {:error, :simulation_not_found}

      _ ->
        {:error, :invalid_state}
    end
  end

  @doc """
  Resumes a paused simulation.

  Uses DETS-based IPC to communicate with the Tick object in the
  running simulation process.
  """
  @spec resume(String.t()) :: :ok | {:error, term()}
  def resume(swarm_name) do
    case RuntimeStore.get_status(swarm_name) do
      :paused ->
        # Request resume via DETS IPC - Tick will poll and act on this
        RuntimeStore.request_resume(swarm_name)
        :ok

      :running ->
        {:error, :not_paused}

      status when status in [:halted, :completed] ->
        {:error, :simulation_not_running}

      nil ->
        {:error, :simulation_not_found}

      _ ->
        {:error, :invalid_state}
    end
  end

  @doc """
  Checks if a simulation is paused.
  """
  @spec paused?(String.t()) :: boolean()
  def paused?(swarm_name) do
    RuntimeStore.paused?(swarm_name)
  end

  defp apply_overrides(spec, opts) do
    spec
    |> maybe_override_steps(opts[:steps])
    |> maybe_override_parallel(opts[:parallel])
  end

  defp maybe_override_steps(spec, nil), do: spec
  defp maybe_override_steps(spec, steps), do: %{spec | steps: steps}

  defp maybe_override_parallel(spec, nil), do: spec

  defp maybe_override_parallel(spec, parallel) do
    tick_config = %{spec.tick_config | opts: Map.put(spec.tick_config.opts, :parallel, parallel)}
    %{spec | tick_config: tick_config}
  end
end
