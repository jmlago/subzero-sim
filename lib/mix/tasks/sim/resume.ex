defmodule Mix.Tasks.Sim.Resume do
  @shortdoc "Resume a paused simulation"

  @moduledoc """
  Resumes a paused simulation.

  ## Usage

      mix sim resume <name>

  ## Examples

      mix sim resume market_sim
  """

  use Mix.Task

  alias SubzeroSim.CLI.Output
  alias SubzeroSim.Runner
  alias SubzeroSim.Store.RuntimeStore

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [name] -> resume_simulation(name)
      [] -> Output.error("Usage: mix sim resume <name>")
      _ -> Output.error("Usage: mix sim resume <name>")
    end
  end

  defp resume_simulation(name) do
    case RuntimeStore.get_info(name) do
      nil ->
        Output.error("Simulation not found: #{name}")

      %{status: :paused, step: step} ->
        Output.info("Resuming simulation #{name} from step #{step}...")

        case Runner.resume(name) do
          :ok ->
            # Wait for the resume to be acknowledged (IPC has ~500ms latency)
            wait_for_resume(name, 5)

          {:error, reason} ->
            Output.error("Failed to resume: #{inspect(reason)}")
        end

      %{status: :running} ->
        Output.info("Simulation #{name} is already running")

      %{status: status} when status in [:halted, :completed] ->
        Output.error("Cannot resume simulation that is #{status}")

      %{status: status} ->
        Output.error("Cannot resume simulation in status: #{status}")
    end
  end

  defp wait_for_resume(name, retries) when retries > 0 do
    Process.sleep(300)

    case RuntimeStore.get_status(name) do
      :running ->
        Output.success("Simulation resumed")

      :paused ->
        wait_for_resume(name, retries - 1)

      other ->
        Output.error("Unexpected status: #{other}")
    end
  end

  defp wait_for_resume(name, 0) do
    Output.warning("Resume request sent but not yet acknowledged. Check `mix sim status #{name}`")
  end
end
