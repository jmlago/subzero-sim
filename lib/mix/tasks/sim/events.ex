defmodule Mix.Tasks.Sim.Events do
  @shortdoc "Query simulation events"

  @moduledoc """
  Query events from simulations.

  ## Usage

      mix sim events [options]

  ## Options

      --sim NAME          Filter by simulation name
      --agent NAME        Filter by agent name
      --category CAT      Filter by category (tick, metrics, agent)
      --errors            Show only errors
      --warnings          Show warnings and errors
      --limit N           Maximum events to return (default: 50)
      --minutes N         Events from the last N minutes
      --help, -h          Show this help

  ## Categories

      tick      - Tick events (step_started, step_completed, halted)
      metrics   - Metrics events (state_collected, halt_condition_checked)
      agent     - Agent events (started, stopped, stdout, messages)

  ## Examples

      mix sim events
      mix sim events --sim market_sim
      mix sim events --sim market_sim --agent buyer_1
      mix sim events --errors
      mix sim events --category tick --limit 100
  """

  use Mix.Task

  alias SubzeroSim.CLI.Output

  @impl true
  def run(args) do
    {opts, _rest, _} =
      OptionParser.parse(args,
        strict: [
          sim: :string,
          agent: :string,
          category: :string,
          errors: :boolean,
          warnings: :boolean,
          limit: :integer,
          minutes: :integer,
          help: :boolean
        ],
        aliases: [s: :sim, a: :agent, e: :errors, w: :warnings, n: :minutes, h: :help]
      )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
    else
      Mix.Task.run("app.start")
      query_events(opts)
    end
  end

  defp query_events(opts) do
    query_opts = build_query_opts(opts)
    events = do_query(query_opts)

    if Enum.empty?(events) do
      Output.dim("No events found")
    else
      Output.header("Events (#{length(events)})")
      Enum.each(events, &format_event/1)
    end
  end

  defp do_query(query_opts) do
    try do
      SubzeroclawSwarm.CLI.SwarmRegistry.query_events(query_opts)
    rescue
      _ -> []
    end
  end

  defp build_query_opts(opts) do
    query_opts = []

    query_opts =
      cond do
        opts[:errors] -> Keyword.put(query_opts, :level, :error)
        opts[:warnings] -> Keyword.put(query_opts, :level, [:error, :warning])
        true -> query_opts
      end

    query_opts =
      if opts[:minutes] do
        Keyword.put(query_opts, :minutes, opts[:minutes])
      else
        query_opts
      end

    query_opts =
      if opts[:sim] do
        Keyword.put(query_opts, :swarm, opts[:sim])
      else
        query_opts
      end

    query_opts =
      if opts[:agent] do
        Keyword.put(query_opts, :agent, String.to_atom(opts[:agent]))
      else
        query_opts
      end

    query_opts =
      if opts[:category] do
        Keyword.put(query_opts, :category, String.to_atom(opts[:category]))
      else
        query_opts
      end

    query_opts =
      if opts[:limit] do
        Keyword.put(query_opts, :limit, opts[:limit])
      else
        Keyword.put(query_opts, :limit, 50)
      end

    query_opts
  end

  defp format_event(event) do
    timestamp = format_timestamp(event.timestamp)
    level = format_level(event.level)
    category = Output.colorize("[#{event.category}]", :dim)

    # Build context string
    context_parts = []
    context_parts = if event.swarm, do: context_parts ++ [event.swarm], else: context_parts

    context_parts =
      if event.agent, do: context_parts ++ [to_string(event.agent)], else: context_parts

    context =
      if context_parts == [],
        do: "",
        else: " " <> Output.colorize(Enum.join(context_parts, "/"), :cyan)

    event_type = Output.colorize("#{event.event_type}", :white)

    Output.puts("#{timestamp} #{level} #{category}#{context} #{event_type}")
    Output.puts("  #{event.message}")

    # Show relevant metadata
    if map_size(event.metadata) > 0 do
      useful_meta =
        event.metadata
        |> Map.drop([:output_snippet, :buffer_tail, :last_logs])
        |> Enum.take(3)

      unless Enum.empty?(useful_meta) do
        meta_str =
          Enum.map(useful_meta, fn {k, v} ->
            value =
              if is_binary(v) and String.length(v) > 50 do
                String.slice(v, 0, 50) <> "..."
              else
                inspect(v)
              end

            "#{k}=#{value}"
          end)
          |> Enum.join(" ")

        Output.puts("  " <> Output.colorize(meta_str, :dim))
      end
    end
  end

  defp format_timestamp(datetime) when is_binary(datetime) do
    time =
      case String.split(datetime, " ") do
        [_, time_part] -> String.slice(time_part, 0, 8)
        _ -> datetime
      end

    Output.colorize("[#{time}]", :dim)
  end

  defp format_timestamp(%DateTime{} = datetime) do
    time = Calendar.strftime(datetime, "%H:%M:%S")
    Output.colorize("[#{time}]", :dim)
  end

  defp format_timestamp(_), do: Output.colorize("[--:--:--]", :dim)

  defp format_level(:error), do: Output.colorize("ERROR", :red)
  defp format_level(:warning), do: Output.colorize("WARN ", :yellow)
  defp format_level(:info), do: Output.colorize("INFO ", :cyan)
  defp format_level(:debug), do: Output.colorize("DEBUG", :dim)
  defp format_level("error"), do: Output.colorize("ERROR", :red)
  defp format_level("warning"), do: Output.colorize("WARN ", :yellow)
  defp format_level("info"), do: Output.colorize("INFO ", :cyan)
  defp format_level("debug"), do: Output.colorize("DEBUG", :dim)
  defp format_level(other), do: to_string(other)
end
