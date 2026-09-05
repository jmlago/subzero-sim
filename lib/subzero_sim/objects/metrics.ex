defmodule SubzeroSim.Objects.Metrics do
  @moduledoc """
  ObjectHandler for metrics collection and halt condition evaluation.

  The Metrics object:
  - Collects state reports from all agents
  - Computes metrics at each step
  - Evaluates halt conditions
  - Signals the Tick object when steps complete

  ## Message Protocol

  Inbound:
  - `{"action": "state_report", "data": {"state": {...}}}` - Agent state report
  - `{"action": "round_complete", "data": {"step": N}}` - From Tick (turn_based mode)
  - `{"action": "query", "data": {"metric": "name"}}` - Query a metric value

  Outbound:
  - `{"action": "request_state", "data": {"step": N}}` - Request states from agents
  - `{"action": "step_complete"}` - Signal Tick that step is complete
  - `{"action": "halt", "data": {"reason": "..."}}` - Signal halt condition met
  """

  @behaviour Genswarms.Objects.ObjectHandler

  require Logger

  alias SubzeroSim.Store.{MetricsStore, StateStore}
  alias SubzeroSim.Spec.HaltCondition

  defstruct [
    :sim_name,
    :agent_names,
    :measures,
    :halt_conditions,
    :pending_states,
    :current_step,
    :retry_count,
    :waiting_for_step,
    :tick_mode,
    state_report_timeout: 5_000,
    max_retries: 3
  ]

  @impl true
  def init(config) do
    state = %__MODULE__{
      sim_name: config[:sim_name],
      agent_names: config[:agent_names] || [],
      measures: config[:measures] || [],
      halt_conditions: config[:halt_conditions] || [],
      pending_states: MapSet.new(),
      current_step: 0,
      retry_count: 0,
      waiting_for_step: nil,
      tick_mode: config[:tick_mode] || :state_reports,
      state_report_timeout: config[:state_report_timeout] || 5_000,
      max_retries: config[:max_retries] || 3
    }

    # Initialize stores
    MetricsStore.ensure_table()
    StateStore.ensure_table()

    {:ok, state}
  end

  @impl true
  def handle_info({:check_state_reports, step}, state) do
    # Only process if we're still waiting for this step
    if state.waiting_for_step == step and state.current_step == step do
      # Check which agents haven't reported
      missing_agents =
        state.agent_names
        |> Enum.reject(&MapSet.member?(state.pending_states, &1))

      if length(missing_agents) > 0 do
        if state.retry_count < state.max_retries do
          Logger.debug(
            "[Metrics] Step #{step}: #{length(missing_agents)} agents haven't reported, " <>
              "retry #{state.retry_count + 1}/#{state.max_retries}. Missing: #{inspect(missing_agents)}"
          )

          # Schedule next check
          schedule_state_check(step, state.state_report_timeout)

          # Rebroadcast request_state to remind agents
          state = %{state | retry_count: state.retry_count + 1}
          {:broadcast, encode_request_state(step), state}
        else
          Logger.warning(
            "[Metrics] Step #{step}: Max retries reached. Missing agents: #{inspect(missing_agents)}. " <>
              "Proceeding with partial state reports."
          )

          # Complete step with partial data
          complete_step(state)
        end
      else
        # All agents reported, nothing to do (step should have already completed)
        {:noreply, state}
      end
    else
      # Stale timeout, ignore
      {:noreply, state}
    end
  end

  @impl true
  def interface do
    %{
      state_report: %{
        input: ~s({"action": "state_report", "data": {"state": {...}}}),
        output: "Collects state, may trigger metrics computation"
      },
      query: %{
        input: ~s({"action": "query", "data": {"metric": "name"}}),
        output: ~s({"metric": "name", "value": ...})
      }
    }
  end

  @impl true
  def handle_message(from, content, state) do
    case Jason.decode(content) do
      {:ok, msg} ->
        handle_action(from, msg, state)

      {:error, _} ->
        Logger.warning("[Metrics] Invalid JSON from #{from}: #{content}")
        {:noreply, state}
    end
  end

  # Action handlers

  defp handle_action(from, %{"action" => "state_report", "data" => data}, state) do
    agent_state = Map.get(data, "state", %{})
    step = state.current_step

    # Store the state
    StateStore.put(state.sim_name, from, step, agent_state)

    # Track that this agent has reported
    pending = MapSet.put(state.pending_states, from)
    state = %{state | pending_states: pending}

    # Check if all agents have reported
    all_reported? = Enum.all?(state.agent_names, &MapSet.member?(pending, &1))

    if all_reported? do
      complete_step(state)
    else
      {:noreply, state}
    end
  end

  defp handle_action(_from, %{"action" => "round_complete", "data" => data}, state) do
    step = Map.get(data, "step", state.current_step)
    state = %{state | current_step: step}

    # Request states from all agents
    {:broadcast, encode_request_state(step), state}
  end

  defp handle_action(_from, %{"action" => "new_step", "data" => data}, state) do
    step = Map.get(data, "step", state.current_step + 1)
    state = %{state | current_step: step, pending_states: MapSet.new(), retry_count: 0, waiting_for_step: step}
    # Schedule a check for state reports
    schedule_state_check(step)
    {:noreply, state}
  end

  defp handle_action(_from, %{"action" => "start_step", "data" => data}, state) do
    # Called by Tick at simulation start to kick off the first step
    # Broadcasts new_step to all agents
    step = Map.get(data, "step", 1)
    state = %{state | current_step: step, pending_states: MapSet.new(), retry_count: 0, waiting_for_step: step}
    # Schedule a check for state reports
    schedule_state_check(step)
    {:broadcast, encode_new_step(step), state}
  end

  defp handle_action(_from, %{"action" => "start_turn", "data" => data}, state) do
    # Called by Tick for parallel turn_based mode
    # Broadcasts your_turn to all agents
    step = Map.get(data, "step", 1)
    state = %{state | current_step: step, pending_states: MapSet.new(), retry_count: 0, waiting_for_step: step}
    # Schedule a check for state reports
    schedule_state_check(step)
    {:broadcast, encode_your_turn(step), state}
  end

  defp handle_action(_from, %{"action" => "query", "data" => data}, state) do
    response =
      case data do
        %{"metric" => metric_name} ->
          metric_atom = String.to_existing_atom(metric_name)

          case MetricsStore.get_latest(state.sim_name, metric_atom) do
            {step, value} ->
              Jason.encode!(%{metric: metric_name, step: step, value: value})

            nil ->
              Jason.encode!(%{error: "Metric not found: #{metric_name}"})
          end

        %{"all" => true} ->
          metrics = MetricsStore.get_current(state.sim_name)
          Jason.encode!(%{metrics: metrics, step: state.current_step})

        _ ->
          Jason.encode!(%{error: "Invalid query"})
      end

    {:reply, response, state}
  rescue
    ArgumentError ->
      {:reply, Jason.encode!(%{error: "Unknown metric"}), state}
  end

  defp handle_action(from, msg, state) do
    Logger.debug("[Metrics] Unhandled message from #{from}: #{inspect(msg)}")
    {:noreply, state}
  end

  # Step completion logic

  defp complete_step(state) do
    step = state.current_step

    # Get all agent states for this step
    states = StateStore.get_all_states(state.sim_name, step)

    # Compute metrics
    compute_metrics(state, step, states)

    # Get current metrics for halt condition evaluation
    current_metrics = MetricsStore.get_current(state.sim_name)

    # Check halt conditions
    case check_halt_conditions(state.halt_conditions, step, current_metrics, state.sim_name) do
      {:halt, reason} ->
        Logger.info("[Metrics] Halt condition met: #{reason}")
        state = %{state | pending_states: MapSet.new(), waiting_for_step: nil}
        {:send, :tick, encode_halt(reason), state}

      :continue ->
        state = %{state | pending_states: MapSet.new(), waiting_for_step: nil}
        if state.tick_mode == :pipeline do
          # Pipeline mode: don't send step_complete — coordinator controls advancement
          {:noreply, state}
        else
          {:send, :tick, encode_step_complete(), state}
        end
    end
  end

  defp schedule_state_check(step, timeout \\ 5_000) do
    Process.send_after(self(), {:check_state_reports, step}, timeout)
  end

  defp compute_metrics(state, step, states) do
    Enum.each(state.measures, fn measure ->
      # Check if we should compute this metric at this step
      if rem(step, measure.every) == 0 do
        try do
          value = measure.function.(states)
          MetricsStore.put(state.sim_name, measure.name, step, value)
          Logger.debug("[Metrics] #{measure.name} at step #{step}: #{inspect(value)}")
        rescue
          e ->
            Logger.error(
              "[Metrics] Error computing #{measure.name}: #{Exception.message(e)}"
            )
        end
      end
    end)
  end

  defp check_halt_conditions(conditions, step, metrics, sim_name) do
    # Get metric history for conditions that need it
    history = get_metric_history(sim_name)

    Enum.find_value(conditions, :continue, fn condition ->
      if HaltCondition.evaluate(condition, step, metrics, history) do
        reason = format_halt_reason(condition)
        {:halt, reason}
      else
        false
      end
    end)
  end

  defp get_metric_history(sim_name) do
    # Get all metrics as time series
    MetricsStore.export(sim_name)
    |> Enum.map(fn {metric, series} ->
      # Convert from %{step: s, value: v} to {s, v} tuples
      tuples = Enum.map(series, fn %{step: s, value: v} -> {s, v} end)
      {metric, tuples}
    end)
    |> Map.new()
  end

  defp format_halt_reason(condition) do
    case condition.type do
      :after_steps ->
        "after_#{condition.value}_steps"

      :when_predicate ->
        "predicate_met"

      :when_history ->
        "history_predicate_met"

      :metric_converged ->
        "#{condition.value.metric}_converged"

      :metric_plateaued ->
        "#{condition.value.metric}_plateaued"
    end
  end

  # Message encoding

  defp encode_request_state(step) do
    Jason.encode!(%{action: "request_state", data: %{step: step}})
  end

  defp encode_step_complete do
    Jason.encode!(%{action: "step_complete"})
  end

  defp encode_halt(reason) do
    Jason.encode!(%{action: "halt", data: %{reason: reason}})
  end

  defp encode_new_step(step) do
    Jason.encode!(%{action: "new_step", data: %{step: step}})
  end

  defp encode_your_turn(step) do
    Jason.encode!(%{action: "your_turn", data: %{step: step}})
  end
end
