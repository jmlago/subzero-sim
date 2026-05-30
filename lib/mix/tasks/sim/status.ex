defmodule Mix.Tasks.Sim.Status do
  @shortdoc "Show running simulations"

  @moduledoc """
  Shows the status of running simulations.

  ## Usage

      mix sim status             # Show all simulations
      mix sim status <name>      # Show specific simulation details

  ## Examples

      mix sim status
      mix sim status market_sim
  """

  use Mix.Task

  alias SubzeroSim.CLI.Output
  alias SubzeroSim.Store.{RuntimeStore, MetricsStore}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [] -> show_all()
      [name] -> show_detail(name)
      _ -> Output.error("Usage: mix sim status [name]")
    end
  end

  defp show_all do
    Output.header("Simulations")

    sims = RuntimeStore.list_simulations()

    if Enum.empty?(sims) do
      Output.dim("No simulations running")
      Output.dim("Start one with: mix sim run <file.sim>")
    else
      headers = ["Name", "Status", "Step", "Agents", "Started"]

      rows =
        Enum.map(sims, fn sim ->
          step_str = format_step(sim)
          status_str = format_status(sim.status)
          agents_str = to_string(length(sim.agent_names || []))
          started_str = format_time(sim.started_at)
          [sim.name, status_str, step_str, agents_str, started_str]
        end)

      Output.table(headers, rows)

      running = Enum.count(sims, &(&1.status == :running))
      paused = Enum.count(sims, &(&1.status == :paused))
      Output.newline()

      summary =
        if paused > 0 do
          "#{running} running, #{paused} paused, #{length(sims)} total"
        else
          "#{running} running, #{length(sims)} total"
        end

      Output.dim(summary)
    end
  end

  defp show_detail(name) do
    case RuntimeStore.get_info(name) do
      nil ->
        Output.error("Simulation not found: #{name}")

      sim ->
        Output.header("Simulation: #{name}")
        Output.newline()

        Output.puts(Output.kv("Status", format_status(sim.status)))
        Output.puts(Output.kv("Step", format_step(sim)))
        Output.puts(Output.kv("Mode", format_mode(sim)))

        if sim.agent_names do
          Output.puts(Output.kv("Agents", Enum.join(sim.agent_names, ", ")))
        end

        Output.puts(Output.kv("Started", format_time(sim.started_at)))

        if sim.halt_reason do
          Output.puts(Output.kv("Halt reason", sim.halt_reason))
        end

        # Show current metrics
        metrics = MetricsStore.get_current(name)

        if map_size(metrics) > 0 do
          Output.newline()
          Output.puts(Output.colorize("Metrics:", :bold))

          Enum.each(metrics, fn {metric_name, value} ->
            Output.puts("  #{metric_name}: #{inspect(value)}")
          end)
        end
    end
  end

  defp format_step(%{step: step, max_steps: max}) when not is_nil(max) do
    "#{step}/#{max}"
  end

  defp format_step(%{step: step}) do
    to_string(step)
  end

  defp format_status(:running), do: Output.colorize("running", :green)
  defp format_status(:paused), do: Output.colorize("paused", :yellow)
  defp format_status(:halted), do: Output.colorize("halted", :red)
  defp format_status(:completed), do: Output.colorize("completed", :cyan)
  defp format_status(status), do: to_string(status)

  defp format_mode(%{mode: mode, opts: opts}) do
    parallel = Map.get(opts || %{}, :parallel, false)

    if mode == :turn_based and parallel do
      "#{mode} (parallel)"
    else
      to_string(mode)
    end
  end

  defp format_mode(_), do: "-"

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(time) when is_binary(time), do: time
  defp format_time(_), do: "-"
end
