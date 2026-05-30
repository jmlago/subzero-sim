defmodule Mix.Tasks.Sim.Cleanup do
  @moduledoc """
  Cleans up simulation data from DETS stores.

  ## Usage

      mix sim cleanup [name]        # Clean specific simulation
      mix sim cleanup --all         # Clean all simulations
      mix sim cleanup --completed   # Clean only completed/halted simulations

  ## Options

    * `--all` - Clean all simulation data
    * `--completed` - Clean only completed or halted simulations
    * `--force` - Don't prompt for confirmation

  ## Examples

      # Clean up a specific simulation
      mix sim cleanup my_simulation

      # Clean all completed simulations
      mix sim cleanup --completed

      # Clean everything without prompting
      mix sim cleanup --all --force
  """

  use Mix.Task

  alias SubzeroSim.Store.{RuntimeStore, MetricsStore, StateStore}
  alias SubzeroSim.CLI.Output

  @shortdoc "Cleans up simulation data"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, names, _} =
      OptionParser.parse(args,
        strict: [
          all: :boolean,
          completed: :boolean,
          force: :boolean
        ]
      )

    cond do
      opts[:all] ->
        cleanup_all(opts[:force])

      opts[:completed] ->
        cleanup_completed(opts[:force])

      length(names) > 0 ->
        Enum.each(names, &cleanup_simulation/1)

      true ->
        show_usage()
    end
  end

  defp cleanup_all(force?) do
    simulations = RuntimeStore.list_simulations()

    if Enum.empty?(simulations) do
      IO.puts("No simulations to clean up.")
      return_ok()
    end

    IO.puts("Found #{length(simulations)} simulation(s):")
    Enum.each(simulations, fn sim ->
      IO.puts("  - #{sim.name} (#{sim.status})")
    end)

    if force? or confirm?("Clean up ALL simulation data?") do
      Enum.each(simulations, fn sim ->
        do_cleanup(sim.name)
      end)
      Output.success("Cleaned up #{length(simulations)} simulation(s)")
    else
      IO.puts("Cancelled.")
    end
  end

  defp cleanup_completed(force?) do
    simulations = RuntimeStore.list_simulations()
    completed = Enum.filter(simulations, fn s -> s.status in [:completed, :halted] end)

    if Enum.empty?(completed) do
      IO.puts("No completed simulations to clean up.")
      return_ok()
    end

    IO.puts("Found #{length(completed)} completed simulation(s):")
    Enum.each(completed, fn sim ->
      IO.puts("  - #{sim.name} (#{sim.status})")
    end)

    if force? or confirm?("Clean up completed simulations?") do
      Enum.each(completed, fn sim ->
        do_cleanup(sim.name)
      end)
      Output.success("Cleaned up #{length(completed)} simulation(s)")
    else
      IO.puts("Cancelled.")
    end
  end

  defp cleanup_simulation(name) do
    case RuntimeStore.get_info(name) do
      nil ->
        Output.error("Simulation not found: #{name}")

      info ->
        if info.status == :running do
          Output.error("Cannot clean up running simulation: #{name}")
          Output.info("Stop it first with: mix sim stop #{name}")
        else
          do_cleanup(name)
          Output.success("Cleaned up: #{name}")
        end
    end
  end

  defp do_cleanup(name) do
    RuntimeStore.cleanup(name)
    MetricsStore.cleanup(name)
    StateStore.cleanup(name)
  end

  defp confirm?(prompt) do
    response = IO.gets("#{prompt} [y/N] ") |> String.trim() |> String.downcase()
    response in ["y", "yes"]
  end

  defp show_usage do
    IO.puts("""
    Usage:
      mix sim cleanup <name>       Clean specific simulation
      mix sim cleanup --all        Clean all simulations
      mix sim cleanup --completed  Clean only completed simulations

    Options:
      --force    Don't prompt for confirmation
    """)
  end

  defp return_ok, do: :ok
end
