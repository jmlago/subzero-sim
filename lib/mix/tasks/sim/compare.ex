defmodule Mix.Tasks.Sim.Compare do
  @moduledoc """
  Runs multiple simulations and compares their metrics.

  This task runs each specified simulation to completion, collects the final
  values of specified metrics, and outputs a comparison table.

  ## Usage

      mix sim.compare file1.sim file2.sim [options]

  ## Options

    * `--metric NAME` - Metric to compare (can be specified multiple times)
    * `--all-metrics` - Compare all available metrics
    * `--steps N` - Override max steps for all simulations
    * `--timeout MS` - Timeout per simulation in milliseconds
    * `--json` - Output results as JSON
    * `--csv` - Output results as CSV
    * `--parallel` - Run simulations in parallel (experimental)

  ## Examples

      # Compare total wealth across two market configurations
      mix sim.compare market_v1.sim market_v2.sim --metric total_wealth

      # Compare multiple metrics
      mix sim.compare sim1.sim sim2.sim --metric wealth --metric trades

      # Compare all metrics
      mix sim.compare sim1.sim sim2.sim --all-metrics

      # Export comparison as CSV
      mix sim.compare sim1.sim sim2.sim --metric wealth --csv > results.csv
  """

  use Mix.Task

  alias SubzeroSim.{Loader, Validator, Runner}

  @shortdoc "Runs and compares multiple simulations"

  @impl true
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    {opts, files, _invalid} =
      OptionParser.parse(args,
        strict: [
          metric: [:string, :keep],
          all_metrics: :boolean,
          steps: :integer,
          timeout: :integer,
          json: :boolean,
          csv: :boolean,
          parallel: :boolean
        ]
      )

    if length(files) < 2 do
      Mix.shell().error("Usage: mix sim.compare <file1.sim> <file2.sim> [more files...] [options]")
      Mix.shell().error("At least two simulation files are required.")
      exit({:shutdown, 1})
    end

    metrics_to_compare = Keyword.get_values(opts, :metric)

    if Enum.empty?(metrics_to_compare) and not opts[:all_metrics] do
      Mix.shell().error("Specify metrics to compare with --metric NAME or --all-metrics")
      exit({:shutdown, 1})
    end

    # Run all simulations
    results =
      if opts[:parallel] do
        run_parallel(files, opts)
      else
        run_sequential(files, opts)
      end

    # Check for failures
    {successes, failures} = Enum.split_with(results, fn {_, r} -> r[:success] end)

    if not Enum.empty?(failures) do
      Mix.shell().error("Some simulations failed:")

      Enum.each(failures, fn {file, result} ->
        Mix.shell().error("  #{file}: #{result[:error]}")
      end)
    end

    if Enum.empty?(successes) do
      Mix.shell().error("No simulations completed successfully.")
      exit({:shutdown, 1})
    end

    # Determine which metrics to compare
    all_metrics =
      successes
      |> Enum.flat_map(fn {_, r} -> Map.keys(r[:metrics] || %{}) end)
      |> Enum.uniq()

    metrics_to_show =
      if opts[:all_metrics] do
        all_metrics
      else
        metrics_to_compare
        |> Enum.map(&String.to_atom/1)
        |> Enum.filter(&(&1 in all_metrics))
      end

    # Output results
    cond do
      opts[:json] ->
        output_json(successes, metrics_to_show)

      opts[:csv] ->
        output_csv(successes, metrics_to_show)

      true ->
        output_table(successes, failures, metrics_to_show)
    end
  end

  defp run_sequential(files, opts) do
    Enum.map(files, fn file ->
      Mix.shell().info("Running: #{file}")
      result = run_simulation(file, opts)
      {file, result}
    end)
  end

  defp run_parallel(files, opts) do
    tasks =
      Enum.map(files, fn file ->
        Task.async(fn ->
          {file, run_simulation(file, opts)}
        end)
      end)

    timeout = opts[:timeout] || 300_000

    Enum.map(tasks, fn task ->
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} -> result
        nil -> {elem(task, 0), %{success: false, error: "timeout"}}
      end
    end)
  end

  defp run_simulation(path, opts) do
    case Loader.load(path) do
      {:ok, spec} ->
        case Validator.validate(spec) do
          :ok ->
            runner_opts =
              opts
              |> Keyword.take([:steps])
              |> Enum.filter(fn {_k, v} -> v != nil end)

            case Runner.start(spec, runner_opts) do
              {:ok, swarm_name} ->
                wait_opts =
                  case opts[:timeout] do
                    nil -> [timeout: 300_000]
                    ms -> [timeout: ms]
                  end

                case Runner.wait_for_completion(swarm_name, wait_opts) do
                  {:ok, info} ->
                    %{
                      success: true,
                      name: spec.name,
                      final_step: info.final_step,
                      metrics: info.metrics,
                      status: info.status
                    }

                  {:error, :timeout} ->
                    Runner.stop(swarm_name)
                    %{success: false, error: "timeout"}
                end

              {:error, reason} ->
                %{success: false, error: "start failed: #{inspect(reason)}"}
            end

          {:error, errors} ->
            %{success: false, error: "validation failed: #{Enum.join(errors, ", ")}"}
        end

      {:error, reason} ->
        %{success: false, error: "load failed: #{inspect(reason)}"}
    end
  end

  defp output_table(successes, failures, metrics) do
    # Calculate column widths
    file_width =
      successes
      |> Enum.map(fn {f, _} -> String.length(Path.basename(f)) end)
      |> Enum.max(fn -> 10 end)
      |> max(10)

    metric_width = 15

    # Header
    header =
      String.pad_trailing("File", file_width) <>
        " | " <>
        String.pad_trailing("Steps", 6) <>
        " | " <>
        Enum.map_join(metrics, " | ", fn m ->
          String.pad_trailing(to_string(m), metric_width)
        end)

    separator = String.duplicate("-", String.length(header))

    IO.puts("")
    IO.puts(header)
    IO.puts(separator)

    # Data rows
    Enum.each(successes, fn {file, result} ->
      row =
        String.pad_trailing(Path.basename(file), file_width) <>
          " | " <>
          String.pad_trailing(to_string(result[:final_step] || "?"), 6) <>
          " | " <>
          Enum.map_join(metrics, " | ", fn m ->
            value = result[:metrics][m]
            formatted = format_value(value)
            String.pad_trailing(formatted, metric_width)
          end)

      IO.puts(row)
    end)

    IO.puts(separator)
    IO.puts("")
    IO.puts("#{length(successes)} simulations completed, #{length(failures)} failed")
  end

  defp output_json(successes, metrics) do
    data =
      Enum.map(successes, fn {file, result} ->
        metric_values =
          Enum.reduce(metrics, %{}, fn m, acc ->
            Map.put(acc, m, result[:metrics][m])
          end)

        %{
          file: file,
          name: result[:name],
          final_step: result[:final_step],
          metrics: metric_values
        }
      end)

    IO.puts(Jason.encode!(data, pretty: true))
  end

  defp output_csv(successes, metrics) do
    # Header
    header = ["file", "name", "final_step" | Enum.map(metrics, &to_string/1)]
    IO.puts(Enum.join(header, ","))

    # Data rows
    Enum.each(successes, fn {file, result} ->
      row = [
        Path.basename(file),
        result[:name] || "",
        to_string(result[:final_step] || "")
        | Enum.map(metrics, fn m ->
            value = result[:metrics][m]
            format_csv_value(value)
          end)
      ]

      IO.puts(Enum.join(row, ","))
    end)
  end

  defp format_value(nil), do: "-"
  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 4)
  defp format_value(v), do: to_string(v)

  defp format_csv_value(nil), do: ""
  defp format_csv_value(v) when is_binary(v), do: "\"#{v}\""
  defp format_csv_value(v), do: to_string(v)
end
