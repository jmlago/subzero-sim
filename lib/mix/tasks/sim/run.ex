defmodule Mix.Tasks.Sim.Run do
  @moduledoc """
  Runs a simulation from a .sim file.

  ## Usage

      mix sim.run path/to/simulation.sim [options]

  ## Options

    * `--steps N` - Override the maximum number of steps
    * `--parallel` - Enable parallel mode for turn_based simulations
    * `--no-parallel` - Disable parallel mode
    * `--quiet` - Suppress progress output
    * `--metrics FILE` - Export final metrics to FILE (JSON format)
    * `--csv FILE` - Export metrics as CSV files (one per metric)
    * `--timeout MS` - Maximum runtime in milliseconds

  ## Examples

      # Run a simulation
      mix sim.run examples/market.sim

      # Run with 50 steps maximum
      mix sim.run examples/market.sim --steps 50

      # Run quietly and export metrics
      mix sim.run examples/market.sim --quiet --metrics results.json

      # Run with timeout
      mix sim.run examples/market.sim --timeout 60000
  """

  use Mix.Task

  alias SubzeroSim.{Loader, Validator, Runner}

  @shortdoc "Runs a simulation from a .sim file"

  @impl true
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    {opts, rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          steps: :integer,
          parallel: :boolean,
          quiet: :boolean,
          metrics: :string,
          csv: :string,
          timeout: :integer
        ]
      )

    case rest do
      [path] ->
        run_simulation(path, opts)

      [] ->
        Mix.shell().error("Usage: mix sim.run <file.sim> [options]")
        exit({:shutdown, 1})

      _ ->
        Mix.shell().error("Too many arguments. Expected one .sim file path.")
        exit({:shutdown, 1})
    end
  end

  defp run_simulation(path, opts) do
    Mix.shell().info("Loading simulation: #{path}")

    case Loader.load(path) do
      {:ok, spec} ->
        case Validator.validate(spec) do
          :ok ->
            do_run(spec, opts)

          {:error, errors} ->
            Mix.shell().error("Validation failed:")
            Enum.each(errors, &Mix.shell().error("  - #{&1}"))
            exit({:shutdown, 1})
        end

      {:error, reason} ->
        Mix.shell().error("Failed to load simulation: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp do_run(spec, opts) do
    runner_opts =
      opts
      |> Keyword.take([:steps, :parallel])
      |> Enum.filter(fn {_k, v} -> v != nil end)

    Mix.shell().info("Starting simulation: #{spec.name}")
    Mix.shell().info("  Mode: #{spec.tick_config.mode}")
    Mix.shell().info("  Agents: #{length(SubzeroSim.Spec.SimSpec.agent_names(spec))}")

    if spec.steps do
      Mix.shell().info("  Max steps: #{spec.steps}")
    end

    case Runner.start(spec, runner_opts) do
      {:ok, swarm_name} ->
        Mix.shell().info("Simulation started: #{swarm_name}")

        unless opts[:quiet] do
          # Stream progress in a separate process
          spawn(fn -> Runner.stream_progress(swarm_name) end)
        end

        # Wait for completion
        wait_opts =
          case opts[:timeout] do
            nil -> []
            ms -> [timeout: ms]
          end

        case Runner.wait_for_completion(swarm_name, wait_opts) do
          {:ok, info} ->
            Mix.shell().info("")
            Mix.shell().info("Simulation completed!")
            Mix.shell().info("  Final step: #{info.final_step}")
            Mix.shell().info("  Status: #{info.status}")

            if info.halt_reason do
              Mix.shell().info("  Reason: #{info.halt_reason}")
            end

            # Print metrics summary
            if map_size(info.metrics) > 0 do
              Mix.shell().info("")
              Mix.shell().info("Final metrics:")

              Enum.each(info.metrics, fn {name, value} ->
                Mix.shell().info("  #{name}: #{inspect(value)}")
              end)
            end

            # Export metrics if requested
            export_if_requested(swarm_name, opts)

            :ok

          {:error, :timeout} ->
            Mix.shell().error("Simulation timed out after #{opts[:timeout]}ms")
            Runner.stop(swarm_name)
            exit({:shutdown, 1})
        end

      {:error, reason} ->
        Mix.shell().error("Failed to start simulation: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp export_if_requested(swarm_name, opts) do
    if opts[:metrics] do
      Mix.shell().info("")
      Mix.shell().info("Exporting metrics to: #{opts[:metrics]}")
      Runner.export_metrics(swarm_name, opts[:metrics], :json)
    end

    if opts[:csv] do
      Mix.shell().info("Exporting CSV metrics to: #{opts[:csv]}")
      Runner.export_metrics(swarm_name, opts[:csv], :csv)
    end
  end
end
