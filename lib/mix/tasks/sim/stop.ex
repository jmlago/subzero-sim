defmodule Mix.Tasks.Sim.Stop do
  @shortdoc "Stop a running simulation"

  @moduledoc """
  Stops a running simulation.

  ## Usage

      mix sim stop <name>

  ## Examples

      mix sim stop market_sim
  """

  use Mix.Task

  alias SubzeroSim.CLI.Output
  alias SubzeroSim.Runner
  alias SubzeroSim.Store.RuntimeStore

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [name] -> stop_simulation(name)
      [] -> Output.error("Usage: mix sim stop <name>")
      _ -> Output.error("Usage: mix sim stop <name>")
    end
  end

  defp stop_simulation(name) do
    case RuntimeStore.get_info(name) do
      nil ->
        Output.error("Simulation not found: #{name}")

      %{status: status} when status in [:halted, :completed] ->
        Output.info("Simulation #{name} is already #{status}")

      _ ->
        Output.info("Stopping simulation #{name}...")
        Runner.stop(name)
        Output.success("Simulation stopped")
    end
  end
end
