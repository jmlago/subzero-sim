defmodule Mix.Tasks.Sim.Metrics do
  @shortdoc "View and export simulation metrics"

  @moduledoc """
  View and export metrics for a simulation.

  ## Usage

      mix sim metrics <name> [options]

  ## Options

      --history           Show metrics history (all steps)
      --export FILE       Export to JSON file
      --csv DIR           Export as CSV files (one per metric)
      --metric NAME       Show specific metric only
      --help, -h          Show this help

  ## Examples

      mix sim metrics market_sim
      mix sim metrics market_sim --history
      mix sim metrics market_sim --export results.json
      mix sim metrics market_sim --csv metrics/
      mix sim metrics market_sim --metric total_wealth
  """

  use Mix.Task

  alias SubzeroSim.CLI.Output
  alias SubzeroSim.Store.{RuntimeStore, MetricsStore}
  alias SubzeroSim.Runner

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [
          history: :boolean,
          export: :string,
          csv: :string,
          metric: :string,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
    else
      case rest do
        [name] -> show_metrics(name, opts)
        [] -> Output.error("Usage: mix sim metrics <name> [options]")
        _ -> Output.error("Usage: mix sim metrics <name> [options]")
      end
    end
  end

  defp show_metrics(name, opts) do
    case RuntimeStore.get_info(name) do
      nil ->
        Output.error("Simulation not found: #{name}")

      sim ->
        cond do
          opts[:export] ->
            export_json(name, opts[:export])

          opts[:csv] ->
            export_csv(name, opts[:csv])

          opts[:history] ->
            show_history(name, sim, opts[:metric])

          true ->
            show_current(name, sim, opts[:metric])
        end
    end
  end

  defp show_current(name, sim, metric_filter) do
    Output.header("Metrics: #{name}")
    Output.puts(Output.kv("Step", to_string(sim.step)))
    Output.newline()

    metrics = MetricsStore.get_current(name)

    metrics =
      if metric_filter do
        metric_atom = String.to_atom(metric_filter)
        Map.take(metrics, [metric_atom])
      else
        metrics
      end

    if map_size(metrics) == 0 do
      Output.dim("No metrics recorded yet")
    else
      Enum.each(metrics, fn {metric_name, value} ->
        Output.puts("  #{metric_name}: #{format_value(value)}")
      end)
    end
  end

  defp show_history(name, _sim, metric_filter) do
    Output.header("Metrics History: #{name}")

    all_metrics = MetricsStore.export(name)

    all_metrics =
      if metric_filter do
        metric_atom = String.to_atom(metric_filter)
        Map.take(all_metrics, [metric_atom])
      else
        all_metrics
      end

    if map_size(all_metrics) == 0 do
      Output.dim("No metrics recorded yet")
    else
      # Get all steps
      all_steps =
        all_metrics
        |> Map.values()
        |> List.flatten()
        |> Enum.map(& &1.step)
        |> Enum.uniq()
        |> Enum.sort()

      metric_names = Map.keys(all_metrics) |> Enum.sort()

      # Build table
      headers = ["Step" | Enum.map(metric_names, &to_string/1)]

      rows =
        Enum.map(all_steps, fn step ->
          values =
            Enum.map(metric_names, fn metric_name ->
              series = Map.get(all_metrics, metric_name, [])

              case Enum.find(series, &(&1.step == step)) do
                nil -> "-"
                %{value: v} -> format_value(v)
              end
            end)

          [to_string(step) | values]
        end)

      Output.table(headers, rows)
    end
  end

  defp export_json(name, path) do
    Output.info("Exporting metrics to: #{path}")

    case Runner.export_metrics(name, path, :json) do
      :ok ->
        Output.success("Metrics exported to #{path}")

      {:error, reason} ->
        Output.error("Failed to export: #{inspect(reason)}")
    end
  end

  defp export_csv(name, dir) do
    # Ensure directory exists
    File.mkdir_p!(dir)
    base_path = Path.join(dir, "metrics.csv")

    Output.info("Exporting metrics to: #{dir}")

    case Runner.export_metrics(name, base_path, :csv) do
      :ok ->
        Output.success("Metrics exported to #{dir}")

      {:error, reason} ->
        Output.error("Failed to export: #{inspect(reason)}")
    end
  end

  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 4)
  defp format_value(v), do: inspect(v)
end
