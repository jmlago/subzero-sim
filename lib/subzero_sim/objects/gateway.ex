defmodule SubzeroSim.Objects.Gateway do
  @moduledoc """
  ObjectHandler for parent-child simulation communication.

  The Gateway object is automatically injected into child simulations when
  `Runner.start_child/2` is called. It handles:

  1. Receiving "simulation_started" from Tick
  2. Injecting initial_task to the designated agent (inject_to)
  3. Listening for "final_result" from the collect_from agent
  4. Forwarding result to parent process and storing in ResultStore

  ## Message Protocol

  Inbound:
  - `{"action": "simulation_started", "data": {"step": N}}` - From Tick on start
  - `{"action": "final_result", "data": {...}}` - From collect_from agent

  Outbound:
  - `{"action": "initial_task", "data": {...}}` - To inject_to agent
  """

  @behaviour Genswarms.Objects.ObjectHandler

  require Logger

  alias SubzeroSim.Store.ResultStore

  defstruct [
    :sim_name,
    :parent_pid,
    :inject_to,
    :collect_from,
    :initial_task,
    :result,
    result_received: false,
    task_injected: false
  ]

  @impl true
  def init(config) do
    state = %__MODULE__{
      sim_name: config[:sim_name],
      parent_pid: config[:parent_pid],
      inject_to: config[:inject_to],
      collect_from: config[:collect_from],
      initial_task: config[:initial_task],
      result: nil,
      task_injected: false
    }

    Logger.debug("[Gateway] Initialized for #{state.sim_name}")
    {:ok, state}
  end

  @impl true
  def interface do
    %{
      simulation_started: %{
        input: ~s({"action": "simulation_started", "data": {"step": N}}),
        output: ~s({"action": "initial_task", "data": {...}})
      },
      final_result: %{
        input: ~s({"action": "final_result", "data": {...}}),
        output: "Stores result and notifies parent process"
      }
    }
  end

  @impl true
  def handle_message(from, content, state) do
    case Jason.decode(content) do
      {:ok, msg} ->
        handle_action(from, msg, state)

      {:error, _} ->
        Logger.warning("[Gateway] Invalid JSON from #{from}: #{content}")
        {:noreply, state}
    end
  end

  # Handle simulation_started from Tick
  defp handle_action(from, %{"action" => "simulation_started", "data" => _data}, state)
       when from in [:tick, "tick"] do
    if state.task_injected or is_nil(state.inject_to) or is_nil(state.initial_task) do
      {:noreply, state}
    else
      Logger.info("[Gateway] Simulation started, injecting task to #{state.inject_to}")
      state = %{state | task_injected: true}
      msg = encode_initial_task(state.initial_task)
      {:send, state.inject_to, msg, state}
    end
  end

  # Handle final_result from collect_from agent
  defp handle_action(from, %{"action" => "final_result", "data" => data}, state) do
    # Only accept from collect_from agent (or any agent if collect_from not specified)
    valid_sender? = is_nil(state.collect_from) or agent_matches?(from, state.collect_from)

    if valid_sender? and not state.result_received do
      Logger.info("[Gateway] Received final_result from #{from}")

      # Store the result
      ResultStore.put(state.sim_name, data)

      # Notify parent process if present
      if state.parent_pid do
        send(state.parent_pid, {:gateway_result, state.sim_name, data})
      end

      {:noreply, %{state | result: data, result_received: true}}
    else
      Logger.debug(
        "[Gateway] Ignoring final_result from #{from} (expected from #{state.collect_from})"
      )

      {:noreply, state}
    end
  end

  # Ignore bounced messages
  defp handle_action(_from, %{"action" => action}, state)
       when action in ["new_step", "your_turn", "request_state", "initial_task"] do
    {:noreply, state}
  end

  defp handle_action(from, msg, state) do
    Logger.debug("[Gateway] Unhandled message from #{from}: #{inspect(msg)}")
    {:noreply, state}
  end

  # Check if an agent name matches the expected role
  # Handles both exact match and role expansion (e.g., :coordinator matches :coordinator_1)
  defp agent_matches?(agent_name, expected) do
    name = to_string(agent_name)
    role = to_string(expected)

    name == role or
      case String.split(name, role <> "_", parts: 2) do
        ["", suffix] -> Regex.match?(~r/\A[1-9][0-9]*\z/, suffix)
        _ -> false
      end
  end

  defp encode_initial_task(task) do
    Jason.encode!(%{action: "initial_task", data: task})
  end
end
