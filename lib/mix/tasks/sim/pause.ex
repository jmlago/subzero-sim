defmodule Mix.Tasks.Sim.Pause do
  @shortdoc "Pause a running simulation"

  @moduledoc """
  Pauses a running simulation.

  The simulation will stop advancing steps but remain in memory.
  Use `mix sim resume` to continue.

  ## Usage

      mix sim pause <name>

  ## Examples

      mix sim pause market_sim
  """

  use Mix.Task

  alias SubzeroSim.CLI.Output
  alias SubzeroSim.Runner
  alias SubzeroSim.Store.RuntimeStore

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [name] -> pause_simulation(name)
      [] -> Output.error("Usage: mix sim pause <name>")
      _ -> Output.error("Usage: mix sim pause <name>")
    end
  end

  defp pause_simulation(name) do
    case RuntimeStore.get_info(name) do
      nil ->
        Output.error("Simulation not found: #{name}")

      %{status: :paused, step: step} ->
        Output.info("Simulation #{name} is already paused at step #{step}")

      %{status: status} when status in [:halted, :completed] ->
        Output.error("Simulation #{name} is already #{status}")

      %{status: :running, step: step} ->
        Output.info("Pausing simulation #{name} at step #{step}...")

        case Runner.pause(name) do
          :ok ->
            # Wait for the pause to be acknowledged (IPC has ~500ms latency)
            wait_for_pause(name, 5)

          {:error, reason} ->
            Output.error("Failed to pause: #{inspect(reason)}")
        end

      %{status: status} ->
        Output.error("Cannot pause simulation in status: #{status}")
    end
  end

  defp wait_for_pause(name, retries) when retries > 0 do
    Process.sleep(300)

    case RuntimeStore.get_status(name) do
      :paused ->
        Output.success("Simulation paused")

      :running ->
        wait_for_pause(name, retries - 1)

      other ->
        Output.error("Unexpected status: #{other}")
    end
  end

  defp wait_for_pause(name, 0) do
    Output.warning("Pause request sent but not yet acknowledged. Check `mix sim status #{name}`")
  end
end
