defmodule Mix.Tasks.Sim.Logs do
  @shortdoc "View agent logs"

  @moduledoc """
  View agent conversation logs and output for a simulation.

  ## Usage

      mix sim logs <name> [agent] [options]

  ## Options

      --follow, -f        Stream logs in real-time
      --tail N            Show last N entries (default: 50)
      --stdout            Show agent stdout output
      --conversation      Show conversation only (default)
      --all               Show all log types
      --help, -h          Show this help

  ## Examples

      mix sim logs market_sim
      mix sim logs market_sim buyer_1
      mix sim logs market_sim buyer_1 --follow
      mix sim logs market_sim --stdout
      mix sim logs market_sim --all --tail 100
  """

  use Mix.Task

  alias SubzeroSim.CLI.Output
  alias SubzeroSim.Store.RuntimeStore

  # Conversation event types
  @conversation_types [
    :user_message,
    :assistant_response,
    :tool_call,
    :tool_result,
    :system_message
  ]

  # Stdout event types
  @stdout_types [:stdout]

  # All agent event types
  @all_agent_types @conversation_types ++
                     @stdout_types ++
                     [
                       :started,
                       :stopped,
                       :task_sent,
                       :message_received
                     ]

  @impl true
  def run(args) do
    {opts, rest, _} =
      OptionParser.parse(args,
        strict: [
          follow: :boolean,
          tail: :integer,
          stdout: :boolean,
          conversation: :boolean,
          all: :boolean,
          help: :boolean
        ],
        aliases: [f: :follow, n: :tail, h: :help]
      )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
    else
      Mix.Task.run("app.start")

      case rest do
        [name] -> show_logs(name, nil, opts)
        [name, agent] -> show_logs(name, String.to_atom(agent), opts)
        [] -> Output.error("Usage: mix sim logs <name> [agent] [options]")
        _ -> Output.error("Usage: mix sim logs <name> [agent] [options]")
      end
    end
  end

  defp show_logs(name, agent_name, opts) do
    case RuntimeStore.get_info(name) do
      nil ->
        Output.error("Simulation not found: #{name}")

      _sim ->
        if opts[:follow] do
          stream_logs(name, agent_name, opts)
        else
          show_static_logs(name, agent_name, opts)
        end
    end
  end

  defp show_static_logs(name, agent_name, opts) do
    limit = opts[:tail] || 50
    event_types = get_event_types(opts)

    # Try to query from swarm's event store
    events = query_events(name, agent_name, event_types, limit)

    if Enum.empty?(events) do
      Output.dim("No logs found")
      Output.newline()
      Output.dim("Tip: Logs appear once agents start processing.")
    else
      if agent_name do
        Output.header("Logs: #{agent_name}")
      else
        Output.header("Logs: #{name}")
      end

      events
      |> Enum.reverse()
      |> Enum.each(&format_log_entry/1)
    end
  end

  defp stream_logs(name, agent_name, opts) do
    Output.info("Streaming logs... (Ctrl+C to stop)")
    Output.newline()

    event_types = get_event_types(opts)

    # Show recent logs first
    recent = query_events(name, agent_name, event_types, 10)

    unless Enum.empty?(recent) do
      Output.dim("Recent logs:")

      recent
      |> Enum.reverse()
      |> Enum.each(&format_log_entry/1)

      Output.newline()
      Output.dim("--- Live stream ---")
      Output.newline()
    end

    # Try to subscribe to real-time events if available
    try do
      SubzeroclawSwarm.Observability.LogStore.subscribe(name)
      stream_loop(agent_name, event_types)
    rescue
      _ ->
        # Fall back to polling
        poll_loop(name, agent_name, event_types, 0)
    end
  end

  defp stream_loop(agent_filter, event_types) do
    receive do
      {:log_event, event} ->
        matches_agent = is_nil(agent_filter) or event.agent == agent_filter
        matches_type = event.category == :agent and event.event_type in event_types

        if matches_agent and matches_type do
          format_log_entry(event)
        end

        stream_loop(agent_filter, event_types)

      _ ->
        stream_loop(agent_filter, event_types)
    end
  end

  defp poll_loop(name, agent_name, event_types, last_count) do
    events = query_events(name, agent_name, event_types, 100)
    current_count = length(events)

    if current_count > last_count do
      # Show new events
      events
      |> Enum.take(current_count - last_count)
      |> Enum.reverse()
      |> Enum.each(&format_log_entry/1)
    end

    Process.sleep(500)
    poll_loop(name, agent_name, event_types, current_count)
  end

  defp query_events(swarm_name, agent_name, event_types, limit) do
    # Try to use swarm's event store
    try do
      query_opts = [
        swarm: swarm_name,
        category: :agent,
        limit: limit
      ]

      query_opts =
        if agent_name do
          Keyword.put(query_opts, :agent, agent_name)
        else
          query_opts
        end

      SubzeroclawSwarm.CLI.SwarmRegistry.query_events(query_opts)
      |> Enum.filter(fn e ->
        event_type = if is_atom(e.event_type), do: e.event_type, else: String.to_atom(e.event_type)
        event_type in event_types
      end)
    rescue
      _ -> []
    end
  end

  defp get_event_types(opts) do
    cond do
      opts[:all] -> @all_agent_types
      opts[:stdout] -> @stdout_types
      opts[:conversation] -> @conversation_types
      true -> @conversation_types
    end
  end

  defp format_log_entry(event) do
    timestamp = format_timestamp(event.timestamp)
    agent = Output.colorize("[#{event.agent}]", :blue)

    case event.event_type do
      type when type in [:user_message, :assistant_response, :tool_call, :tool_result, :system_message] ->
        format_conversation_entry(event, timestamp, agent)

      :stdout ->
        format_stdout_entry(event, timestamp, agent)

      :task_sent ->
        format_task_entry(event, timestamp, agent)

      :message_received ->
        format_message_entry(event, timestamp, agent)

      _ ->
        format_generic_entry(event, timestamp, agent)
    end
  end

  defp format_conversation_entry(event, timestamp, agent) do
    role = get_metadata(event, :role, "unknown")
    content = get_metadata(event, :content, event.message)

    role_display =
      case role do
        "user" -> Output.colorize("USER", :cyan)
        "asst" -> Output.colorize("ASST", :green)
        "tool" -> Output.colorize("TOOL", :yellow)
        "res" -> Output.colorize("RES ", :dim)
        "sys" -> Output.colorize("SYS ", :magenta)
        _ -> Output.colorize(String.upcase(to_string(role)), :white)
      end

    content_formatted =
      content
      |> to_string()
      |> String.replace("\n", "\n       ")

    Output.puts("#{timestamp} #{agent} #{role_display}: #{content_formatted}")
  end

  defp format_stdout_entry(event, timestamp, agent) do
    output = get_metadata(event, :output, event.message)

    output_formatted =
      output
      |> to_string()
      |> String.trim()
      |> String.replace("\n", "\n       ")

    Output.puts("#{timestamp} #{agent} #{Output.colorize("OUT", :cyan)}: #{output_formatted}")
  end

  defp format_task_entry(event, timestamp, agent) do
    task = get_metadata(event, :task, event.message)
    Output.puts("#{timestamp} #{agent} #{Output.colorize("TASK", :magenta)}: #{task}")
  end

  defp format_message_entry(event, timestamp, agent) do
    from = get_metadata(event, :from, "unknown")
    content = get_metadata(event, :content, event.message)
    Output.puts("#{timestamp} #{agent} #{Output.colorize("MSG<-#{from}", :yellow)}: #{content}")
  end

  defp format_generic_entry(event, timestamp, agent) do
    type = Output.colorize(String.upcase(to_string(event.event_type)), :dim)
    Output.puts("#{timestamp} #{agent} #{type}: #{event.message}")
  end

  defp get_metadata(event, key, default) do
    Map.get(event.metadata, key) ||
      Map.get(event.metadata, to_string(key)) ||
      default
  end

  defp format_timestamp(%DateTime{} = datetime) do
    time = Calendar.strftime(datetime, "%H:%M:%S")
    Output.colorize("[#{time}]", :dim)
  end

  defp format_timestamp(datetime) when is_binary(datetime) do
    time =
      case String.split(datetime, " ") do
        [_date, time_part] ->
          time_part
          |> String.split(".")
          |> List.first()

        _ ->
          datetime
      end

    Output.colorize("[#{time}]", :dim)
  end

  defp format_timestamp(_), do: Output.colorize("[--:--:--]", :dim)
end
