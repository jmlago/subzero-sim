defmodule SubzeroSim do
  @moduledoc """
  SubzeroSim - Domain-agnostic simulation layer on top of subzero-swarms.

  Adds time (ticks), metrics collection, and halt conditions to agent swarms.
  Users write `.sim` files with a DSL, and the compiler generates subzero-swarms configs.

  ## Quick Start

      # Load and run a simulation
      {:ok, spec} = SubzeroSim.load("my_simulation.sim")
      {:ok, swarm_name} = SubzeroSim.run(spec)

      # Or use mix tasks
      # mix sim.run my_simulation.sim
      # mix sim.validate my_simulation.sim
      # mix sim.compare sim1.sim sim2.sim --metric wealth

  ## Architecture

      .sim file → Parser → %SimSpec{} → Compiler → swarm config → subzero-swarms
                                           ↓
                                    Injects Tick + Metrics objects
  """

  alias SubzeroSim.{Loader, Validator, Compiler, Runner}
  alias SubzeroSim.Spec.SimSpec

  @doc """
  Loads a simulation from a .sim file.

  Returns `{:ok, %SimSpec{}}` on success, `{:error, reason}` on failure.
  """
  @spec load(String.t()) :: {:ok, SimSpec.t()} | {:error, term()}
  def load(path) do
    Loader.load(path)
  end

  @doc """
  Validates a SimSpec for coherence.

  Returns `:ok` on success, `{:error, reasons}` on failure.
  """
  @spec validate(SimSpec.t()) :: :ok | {:error, [String.t()]}
  def validate(spec) do
    Validator.validate(spec)
  end

  @doc """
  Compiles a SimSpec into a subzero-swarms config map.
  """
  @spec compile(SimSpec.t()) :: {:ok, map()} | {:error, term()}
  def compile(spec) do
    Compiler.compile(spec)
  end

  @doc """
  Runs a simulation from a SimSpec.

  Options:
    - `:steps` - Override max steps
    - `:parallel` - Override turn_based parallel mode
  """
  @spec run(SimSpec.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(spec, opts \\ []) do
    Runner.start(spec, opts)
  end

  @doc """
  Waits for a simulation to complete.

  Options:
    - `:timeout` - Max wait time in milliseconds (default: :infinity)
  """
  @spec wait(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def wait(swarm_name, opts \\ []) do
    Runner.wait_for_completion(swarm_name, opts)
  end

  @doc """
  Loads, validates, compiles, and runs a simulation in one call.
  """
  @spec run_file(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run_file(path, opts \\ []) do
    with {:ok, spec} <- load(path),
         :ok <- validate(spec),
         spec <- apply_overrides(spec, opts) do
      run(spec, opts)
    end
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
