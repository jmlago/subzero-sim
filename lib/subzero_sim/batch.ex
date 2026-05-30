defmodule SubzeroSim.Batch do
  @moduledoc """
  Batch execution of simulations with resource limits.

  Provides functions to run multiple simulations in parallel with
  configurable concurrency limits.

  ## Examples

      # Run multiple simulations with concurrency limit
      Batch.run([{spec1, opts1}, {spec2, opts2}], max_concurrent: 3)

      # Run variants of a base simulation
      Batch.run_variants(base_spec, [variant_fn1, variant_fn2], max_concurrent: 2)

      # Load and run from file paths
      Batch.run_files(["sim1.sim", "sim2.sim"], max_concurrent: 4)
  """

  require Logger

  alias SubzeroSim.{Loader, Runner}
  alias SubzeroSim.Spec.SimSpec

  @default_max_concurrent 4
  @default_timeout :infinity

  @type sim_input :: {SimSpec.t(), keyword()}
  @type result :: {:ok, map()} | {:error, term()}
  @type batch_result :: %{
          completed: [{SimSpec.t(), result()}],
          failed: [{SimSpec.t(), term()}]
        }

  @doc """
  Runs multiple simulations with concurrency control.

  Takes a list of `{spec, opts}` tuples and runs them in parallel,
  respecting the max_concurrent limit.

  Options:
    - `:max_concurrent` - Maximum number of concurrent simulations (default: 4)
    - `:timeout` - Timeout per simulation in ms (default: :infinity)
    - `:on_complete` - Optional callback `fn spec, result -> any` called when each completes

  Returns a map with `:completed` and `:failed` lists.
  """
  @spec run([sim_input()], keyword()) :: batch_result()
  def run(sim_inputs, opts \\ []) do
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    on_complete = Keyword.get(opts, :on_complete)

    Logger.info("[Batch] Starting batch of #{length(sim_inputs)} simulations (max_concurrent: #{max_concurrent})")

    # Use Task.async_stream for controlled parallelism
    results =
      sim_inputs
      |> Task.async_stream(
        fn {spec, sim_opts} ->
          run_single(spec, sim_opts, timeout)
        end,
        max_concurrency: max_concurrent,
        timeout: timeout_with_buffer(timeout),
        on_timeout: :kill_task
      )
      |> Enum.zip(sim_inputs)
      |> Enum.map(fn {task_result, {spec, _opts}} ->
        result =
          case task_result do
            {:ok, result} -> result
            {:exit, reason} -> {:error, {:exit, reason}}
          end

        if on_complete, do: on_complete.(spec, result)
        {spec, result}
      end)

    # Partition into completed and failed
    {completed, failed} =
      Enum.split_with(results, fn {_spec, result} ->
        match?({:ok, _}, result)
      end)

    Logger.info(
      "[Batch] Batch complete: #{length(completed)} completed, #{length(failed)} failed"
    )

    %{completed: completed, failed: failed}
  end

  @doc """
  Runs variants of a base simulation.

  Takes a base spec and a list of variant functions. Each variant function
  receives the spec and returns a modified spec.

  Options:
    - `:max_concurrent` - Maximum number of concurrent simulations (default: 4)
    - `:timeout` - Timeout per simulation in ms (default: :infinity)
    - `:sim_opts` - Options to pass to each simulation runner

  ## Example

      variants = [
        fn spec -> Variant.set_agent_count(spec, :worker, 5) end,
        fn spec -> Variant.set_agent_count(spec, :worker, 10) end
      ]

      Batch.run_variants(base_spec, variants, max_concurrent: 2)
  """
  @spec run_variants(SimSpec.t(), [(SimSpec.t() -> SimSpec.t())], keyword()) :: batch_result()
  def run_variants(%SimSpec{} = base_spec, variant_fns, opts \\ []) do
    sim_opts = Keyword.get(opts, :sim_opts, [])

    sim_inputs =
      Enum.with_index(variant_fns)
      |> Enum.map(fn {variant_fn, idx} ->
        spec = variant_fn.(base_spec)

        # Ensure unique names if not already set
        spec =
          if spec.name == base_spec.name do
            %{spec | name: "#{base_spec.name}_variant_#{idx + 1}"}
          else
            spec
          end

        {spec, sim_opts}
      end)

    run(sim_inputs, opts)
  end

  @doc """
  Loads and runs simulations from file paths.

  Options:
    - `:max_concurrent` - Maximum number of concurrent simulations (default: 4)
    - `:timeout` - Timeout per simulation in ms (default: :infinity)
    - `:sim_opts` - Options to pass to each simulation runner

  Returns a map with `:completed`, `:failed`, and `:load_errors` lists.
  """
  @spec run_files([String.t()], keyword()) :: map()
  def run_files(paths, opts \\ []) do
    sim_opts = Keyword.get(opts, :sim_opts, [])

    # Load all files first
    {loaded, load_errors} =
      paths
      |> Enum.map(fn path ->
        case Loader.load(path) do
          {:ok, spec} -> {:ok, {spec, sim_opts}}
          {:error, reason} -> {:error, {path, reason}}
        end
      end)
      |> Enum.split_with(fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    sim_inputs = Enum.map(loaded, fn {:ok, input} -> input end)
    errors = Enum.map(load_errors, fn {:error, err} -> err end)

    if length(errors) > 0 do
      Logger.warning("[Batch] Failed to load #{length(errors)} files")
    end

    result = run(sim_inputs, opts)
    Map.put(result, :load_errors, errors)
  end

  @doc """
  Runs simulations sequentially (no parallelism).

  Useful for debugging or when simulations must not run concurrently.
  """
  @spec run_sequential([sim_input()], keyword()) :: batch_result()
  def run_sequential(sim_inputs, opts \\ []) do
    run(sim_inputs, Keyword.put(opts, :max_concurrent, 1))
  end

  # Run a single simulation and wait for completion
  defp run_single(spec, opts, timeout) do
    case Runner.start(spec, opts) do
      {:ok, swarm_name} ->
        wait_opts =
          if timeout == :infinity do
            []
          else
            [timeout: timeout]
          end

        case Runner.wait_for_completion(swarm_name, wait_opts) do
          {:ok, info} -> {:ok, info}
          {:error, reason} -> {:error, {:wait_error, reason}}
        end

      {:error, reason} ->
        {:error, {:start_error, reason}}
    end
  end

  # Add buffer to timeout for Task.async_stream to avoid race conditions
  defp timeout_with_buffer(:infinity), do: :infinity
  defp timeout_with_buffer(ms), do: ms + 5000
end
