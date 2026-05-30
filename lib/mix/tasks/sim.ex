defmodule Mix.Tasks.Sim do
  @shortdoc "SubzeroSim CLI commands"

  @moduledoc """
  CLI commands for SubzeroSim.

  ## Commands

      mix sim run <file.sim>          # Run a simulation
      mix sim validate <files...>     # Validate .sim files
      mix sim compare <files...>      # Compare simulation metrics
      mix sim status [name]           # Show running simulations
      mix sim stop <name>             # Stop a running simulation
      mix sim pause <name>            # Pause a running simulation
      mix sim resume <name>           # Resume a paused simulation
      mix sim logs <name> [agent]     # View agent logs
      mix sim metrics <name>          # View/export metrics
      mix sim events [options]        # Query simulation events
      mix sim cleanup [name|options]  # Clean up simulation data

  ## Examples

      # Run a simulation
      mix sim run examples/market.sim

      # Check status of running simulations
      mix sim status

      # Pause and resume
      mix sim pause market_sim
      mix sim resume market_sim

      # View logs for a specific agent
      mix sim logs market_sim buyer_1 --follow

      # Export metrics
      mix sim metrics market_sim --export results.json

      # Clean up completed simulations
      mix sim cleanup --completed
  """

  use Mix.Task

  @impl true
  def run(args) do
    case args do
      ["run" | rest] -> Mix.Tasks.Sim.Run.run(rest)
      ["validate" | rest] -> Mix.Tasks.Sim.Validate.run(rest)
      ["compare" | rest] -> Mix.Tasks.Sim.Compare.run(rest)
      ["status" | rest] -> Mix.Tasks.Sim.Status.run(rest)
      ["stop" | rest] -> Mix.Tasks.Sim.Stop.run(rest)
      ["pause" | rest] -> Mix.Tasks.Sim.Pause.run(rest)
      ["resume" | rest] -> Mix.Tasks.Sim.Resume.run(rest)
      ["logs" | rest] -> Mix.Tasks.Sim.Logs.run(rest)
      ["metrics" | rest] -> Mix.Tasks.Sim.Metrics.run(rest)
      ["events" | rest] -> Mix.Tasks.Sim.Events.run(rest)
      ["cleanup" | rest] -> Mix.Tasks.Sim.Cleanup.run(rest)
      ["help" | _] -> print_help()
      [] -> print_help()
      [cmd | _] -> unknown_command(cmd)
    end
  end

  defp print_help do
    Mix.shell().info(@moduledoc)
  end

  defp unknown_command(cmd) do
    Mix.shell().error("Unknown command: #{cmd}")
    Mix.shell().info("")
    Mix.shell().info("Run 'mix sim' to see available commands.")
  end
end
