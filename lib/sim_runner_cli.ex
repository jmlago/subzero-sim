defmodule SimRunnerCLI do
  @moduledoc """
  Standalone simulation runner for SubzeroSim .sim files.

  Loads a sim file, runs it for N steps, and prints metrics as JSON.
  The BEAM VM stays warm — no cold-start penalty.

  ## Usage

  As escript:

      sim_runner /path/to/sim.sim                    # Run with defaults (3 steps, 60s timeout)
      sim_runner /path/to/sim.sim --steps 5          # Custom steps
      sim_runner /path/to/sim.sim --timeout 120000   # Custom timeout (ms)

  Output (JSON on last line):

      {"status":"completed","step":3,"metrics":{"total_count":42}}

  ## Build

      mix escript.build --name sim_runner
  """

  def main(args) do
    Application.ensure_all_started(:subzero_sim)

    {opts, paths, _} =
      OptionParser.parse(args,
        strict: [steps: :integer, timeout: :integer, quiet: :boolean]
      )

    steps = opts[:steps] || 3
    timeout = opts[:timeout] || 60_000
    quiet = opts[:quiet] || false

    case paths do
      [] ->
        IO.puts(:stderr, "Usage: sim_runner <sim_file> [--steps N] [--timeout MS]")
        System.halt(1)

      [path | _] ->
        run_sim(path, steps, timeout, quiet)
    end
  end

  defp run_sim(path, steps, timeout, quiet) do
    case SubzeroSim.Loader.load(path) do
      {:ok, spec} ->
        unless quiet, do: IO.puts(:stderr, "Running #{spec.name} (#{steps} steps, #{div(timeout, 1000)}s timeout)...")

        case SubzeroSim.Runner.run_and_collect(spec, steps: steps, timeout: timeout) do
          {:ok, info} ->
            metrics = info[:metrics] || %{}
            result = %{
              status: info[:status] || :unknown,
              step: info[:final_step],
              metrics: metrics
            }
            IO.puts(Jason.encode!(result))

          {:error, reason} ->
            IO.puts(Jason.encode!(%{status: "error", error: inspect(reason), metrics: %{}}))
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "Failed to load: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
