defmodule SubzeroSim.Objects.Tick do
  @moduledoc """
  ObjectHandler for simulation step coordination.

  The Tick object manages simulation time by coordinating steps across agents.
  It supports multiple tick modes for different simulation needs.

  ## Modes

  - `:state_reports` (default) - Passive mode where Metrics signals step completion
  - `:turn_based` - Explicit your_turn/turn_complete coordination
  - `:time_interval` - Timer-based steps at regular intervals
  - `:output_count` - Steps based on total LLM output count

  ## Message Protocol

  Outbound messages:
  - `{"action": "new_step", "data": {"step": N}}` - Broadcast to all agents
  - `{"action": "your_turn", "data": {"step": N}}` - To current agent (turn_based)
  - `{"action": "simulation_halted", "data": {"reason": "...", "step": N}}` - On halt

  Inbound messages:
  - `{"action": "turn_complete"}` - From agent finishing turn (turn_based)
  - `{"action": "output_reported", "data": {"count": N}}` - LLM output count (output_count)
  - `{"action": "step_complete"}` - From Metrics when all states collected
  - `{"action": "halt", "data": {"reason": "..."}}` - Halt signal from Metrics
  """

  @behaviour Genswarms.Objects.ObjectHandler

  require Logger

  alias SubzeroSim.Store.RuntimeStore

  defstruct [
    :sim_name,
    :mode,
    :opts,
    :start_trigger,
    :agent_names,
    :max_steps,
    :current_step,
    :turn_index,
    :output_count,
    :agents_ready,
    :turns_complete,
    :started,
    :halted,
    :paused,
    :has_gateway,
    # For wait_for_objects mode
    :pending_objects,
    :turn_waiting_for_objects
  ]

  @impl true
  def init(config) do
    state = %__MODULE__{
      sim_name: config[:sim_name],
      mode: config[:mode] || :state_reports,
      opts: config[:opts] || %{},
      start_trigger: config[:start_trigger] || :immediate,
      agent_names: config[:agent_names] || [],
      max_steps: config[:max_steps],
      current_step: 0,
      turn_index: 0,
      output_count: 0,
      agents_ready: MapSet.new(),
      turns_complete: MapSet.new(),
      started: false,
      halted: false,
      paused: false,
      has_gateway: config[:has_gateway] || false,
      pending_objects: MapSet.new(),
      turn_waiting_for_objects: false
    }

    # Initialize runtime store with additional info
    RuntimeStore.init_simulation(state.sim_name,
      agent_names: state.agent_names,
      max_steps: state.max_steps,
      mode: state.mode,
      opts: state.opts
    )
    RuntimeStore.set_status(state.sim_name, :initializing)

    # Handle start trigger
    case state.start_trigger do
      :immediate ->
        start_simulation_init(state)

      :on_ready ->
        {:ok, state}

      {:delayed, seconds} ->
        Process.send_after(self(), :start_simulation, seconds * 1000)
        {:ok, state}

      :manual ->
        {:ok, state}
    end
  end

  # Start simulation and return appropriate init response
  defp start_simulation_init(state) do
    state = do_start_simulation(state)
    parallel? = state.opts[:parallel] == true

    # Build list of messages to send
    messages = build_start_messages(state, parallel?)

    # If we have a gateway, add simulation_started message
    messages =
      if state.has_gateway do
        [{:send, :gateway, encode_simulation_started(state.current_step)} | messages]
      else
        messages
      end

    case messages do
      [] ->
        {:ok, state}

      [single] ->
        {:ok, state, single}

      multiple ->
        {:ok, state, {:multi, multiple}}
    end
  end

  defp build_start_messages(state, parallel?) do
    case {state.mode, parallel?} do
      {:turn_based, false} ->
        # Sequential: send your_turn to first agent
        first_agent = Enum.at(state.agent_names, 0)

        if first_agent do
          [{:send, first_agent, encode_your_turn(state.current_step)}]
        else
          []
        end

      {:turn_based, true} ->
        # Parallel: send to metrics which will broadcast your_turn to all
        [{:send, :metrics, encode_start_turn(state.current_step)}]

      _ ->
        # state_reports and other modes: send to metrics which will broadcast new_step
        [{:send, :metrics, encode_start_step(state.current_step)}]
    end
  end

  @impl true
  def interface do
    %{
      new_step: %{
        input: "None (internal trigger)",
        output: ~s({"action": "new_step", "data": {"step": N}})
      },
      your_turn: %{
        input: "None (internal, turn_based mode)",
        output: ~s({"action": "your_turn", "data": {"step": N}})
      },
      turn_complete: %{
        input: ~s({"action": "turn_complete"}),
        output: "Advances to next agent or completes round"
      }
    }
  end

  @impl true
  def handle_message(from, content, state) do
    case Jason.decode(content) do
      {:ok, msg} ->
        handle_action(from, msg, state)

      {:error, _} ->
        Logger.warning("[Tick] Invalid JSON from #{from}: #{content}")
        {:noreply, state}
    end
  end

  # Handle process messages (for timers)
  @impl true
  def handle_info(:start_simulation, state) do
    start_simulation_response(state)
  end

  # IPC check timer - polls DETS for pause/resume requests from CLI
  def handle_info(:check_ipc, state) do
    state = check_ipc_commands(state)
    schedule_ipc_check()
    {:noreply, state}
  end

  # Delayed check for pending objects (wait_for_objects mode)
  def handle_info(:check_objects_ready, state) do
    if state.turn_waiting_for_objects do
      if MapSet.size(state.pending_objects) > 0 do
        Logger.debug("[Tick] Waiting for #{MapSet.size(state.pending_objects)} objects: #{inspect(MapSet.to_list(state.pending_objects))}")
        {:noreply, state}
      else
        Logger.debug("[Tick] All objects ready, advancing turn")
        state = %{state | turn_waiting_for_objects: false}
        do_advance_after_turn(state)
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(:time_tick, state) do
    # Check for IPC commands before processing tick
    state = check_ipc_commands(state)

    if state.started and not state.halted and not state.paused do
      # Check max steps before advancing
      if state.max_steps && state.current_step >= state.max_steps do
        state = %{state | halted: true}
        RuntimeStore.set_status(state.sim_name, :completed)
        Logger.info("[Tick] Simulation #{state.sim_name} completed: max_steps reached")
        {:broadcast, encode_halt("max_steps", state.current_step), state}
      else
        state = advance_step(state)
        schedule_time_tick(state)
        {:broadcast, encode_new_step(state.current_step), state}
      end
    else
      # Re-schedule if paused (will check again later)
      if state.paused do
        schedule_time_tick(state)
      end

      {:noreply, state}
    end
  end

  # Action handlers

  defp handle_action(from, %{"action" => "agent_ready"}, state) do
    if state.start_trigger == :on_ready do
      agents_ready = MapSet.put(state.agents_ready, from)
      state = %{state | agents_ready: agents_ready}

      all_ready? = Enum.all?(state.agent_names, &MapSet.member?(agents_ready, &1))

      if all_ready? do
        start_simulation_response(state)
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp handle_action(_from, %{"action" => "start"}, state) do
    if state.start_trigger == :manual and not state.started do
      start_simulation_response(state)
    else
      {:noreply, state}
    end
  end

  defp handle_action(from, %{"action" => "turn_complete"}, state) when state.mode == :turn_based do
    if state.halted or state.paused or state.turn_waiting_for_objects do
      if state.turn_waiting_for_objects do
        Logger.debug("[Tick] Ignoring turn_complete from #{from} while waiting for objects")
      end
      {:noreply, state}
    else
      handle_turn_complete(from, state)
    end
  end

  defp handle_action(_from, %{"action" => "output_reported", "data" => data}, state)
       when state.mode == :output_count do
    if state.halted do
      {:noreply, state}
    else
      count = Map.get(data, "count", 1)
      new_count = state.output_count + count
      threshold = state.opts[:every] || 10

      if new_count >= threshold do
        state = %{state | output_count: 0}
        state = advance_step(state)
        {:broadcast, encode_new_step(state.current_step), state}
      else
        {:noreply, %{state | output_count: new_count}}
      end
    end
  end

  defp handle_action(_from, %{"action" => "step_complete"}, state) do
    if state.halted or state.paused or state.turn_waiting_for_objects do
      if state.turn_waiting_for_objects do
        Logger.debug("[Tick] Ignoring step_complete while waiting for objects")
      end
      {:noreply, state}
    else
      handle_step_complete(state)
    end
  end

  # Pipeline mode: coordinator explicitly advances the step
  defp handle_action(from, %{"action" => "advance_step"}, state) when state.mode == :pipeline do
    coordinator = state.opts[:coordinator]

    if from == coordinator or coordinator == nil do
      Logger.info("[Tick] Pipeline advance_step from #{from} at step #{state.current_step}")
      handle_step_complete(state)
    else
      Logger.warning("[Tick] Ignoring advance_step from #{from} — expected #{coordinator}")
      {:noreply, state}
    end
  end

  defp handle_action(_from, %{"action" => "halt", "data" => %{"reason" => reason}}, state) do
    state = %{state | halted: true}
    RuntimeStore.set_status(state.sim_name, :halted)
    RuntimeStore.set_halt_reason(state.sim_name, reason)
    Logger.info("[Tick] Simulation #{state.sim_name} halted: #{reason}")

    halt_msg = encode_halt(reason, state.current_step)
    {:broadcast, halt_msg, state}
  end

  # Handle pause request
  defp handle_action(_from, %{"action" => "pause"}, state) do
    if state.started and not state.halted and not state.paused do
      Logger.info("[Tick] Simulation #{state.sim_name} paused at step #{state.current_step}")
      state = %{state | paused: true}
      RuntimeStore.set_paused(state.sim_name, state.current_step)
      {:broadcast, encode_paused(state.current_step), state}
    else
      {:noreply, state}
    end
  end

  # Handle resume request
  defp handle_action(_from, %{"action" => "resume"}, state) do
    if state.paused do
      Logger.info("[Tick] Simulation #{state.sim_name} resumed at step #{state.current_step}")
      state = %{state | paused: false}
      RuntimeStore.clear_paused(state.sim_name)
      {:broadcast, encode_resumed(state.current_step), state}
    else
      {:noreply, state}
    end
  end

  # Object busy/ready signals for wait_for_objects mode
  defp handle_action(from, %{"action" => "object_busy"}, state) do
    if state.opts[:wait_for_objects] do
      Logger.info("[Tick] Object #{from} is busy (pending: #{MapSet.size(state.pending_objects) + 1})")
      pending = MapSet.put(state.pending_objects, from)
      {:noreply, %{state | pending_objects: pending}}
    else
      {:noreply, state}
    end
  end

  defp handle_action(from, %{"action" => "object_ready"}, state) do
    if state.opts[:wait_for_objects] do
      Logger.debug("[Tick] Object #{from} is ready")
      pending = MapSet.delete(state.pending_objects, from)
      state = %{state | pending_objects: pending}

      # If we were waiting for objects and all are now ready, advance the turn
      if state.turn_waiting_for_objects and MapSet.size(pending) == 0 do
        Logger.debug("[Tick] All objects ready, advancing turn")
        state = %{state | turn_waiting_for_objects: false}
        do_advance_after_turn(state)
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Ignore new_step/your_turn bouncing back from metrics broadcast
  defp handle_action(_from, %{"action" => action}, state)
       when action in ["new_step", "your_turn", "simulation_paused", "simulation_resumed"] do
    {:noreply, state}
  end

  defp handle_action(from, msg, state) do
    Logger.debug("[Tick] Unhandled message from #{from}: #{inspect(msg)}")
    {:noreply, state}
  end

  # Mode-specific logic

  # Common start logic - sets state and logs
  defp do_start_simulation(state) do
    state = %{state | started: true, current_step: 1}
    RuntimeStore.set_status(state.sim_name, :running)
    RuntimeStore.set_step(state.sim_name, 1)
    Logger.info("[Tick] Simulation #{state.sim_name} started (mode: #{state.mode})")

    # Schedule IPC check for all modes (pause/resume support)
    schedule_ipc_check()

    case state.mode do
      :time_interval ->
        schedule_time_tick(state)

      _ ->
        :ok
    end

    state
  end

  # For starting simulation from handle_message/handle_info - returns appropriate response
  defp start_simulation_response(state) do
    state = do_start_simulation(state)
    parallel? = state.opts[:parallel] == true

    # Build list of messages to send
    messages = build_start_response_messages(state, parallel?)

    # If we have a gateway, add simulation_started message
    messages =
      if state.has_gateway do
        [{:send, :gateway, encode_simulation_started(state.current_step)} | messages]
      else
        messages
      end

    case messages do
      [] ->
        {:noreply, state}

      [single] ->
        case single do
          {:send, to, msg} -> {:send, to, msg, state}
          {:broadcast, msg} -> {:broadcast, msg, state}
        end

      multiple ->
        {:multi, multiple, state}
    end
  end

  defp build_start_response_messages(state, parallel?) do
    case {state.mode, parallel?} do
      {:turn_based, false} ->
        # Sequential: send your_turn to first agent
        first_agent = Enum.at(state.agent_names, 0)

        if first_agent do
          [{:send, first_agent, encode_your_turn(state.current_step)}]
        else
          []
        end

      {:turn_based, true} ->
        # Parallel: broadcast your_turn to all agents
        [{:broadcast, encode_your_turn(state.current_step)}]

      _ ->
        # Other modes: broadcast new_step
        [{:broadcast, encode_new_step(state.current_step)}]
    end
  end

  defp handle_turn_complete(from, state) do
    # Ignore duplicate turn_complete from same agent
    if MapSet.member?(state.turns_complete, from) do
      Logger.debug("[Tick] Ignoring duplicate turn_complete from #{from}")
      {:noreply, state}
    else
      Logger.debug("[Tick] turn_complete from #{from}, turn_index=#{state.turn_index}, agents=#{inspect(state.agent_names)}")
      turns_complete = MapSet.put(state.turns_complete, from)
      parallel? = state.opts[:parallel] == true

      handle_turn_complete_inner(from, turns_complete, parallel?, state)
    end
  end

  defp handle_turn_complete_inner(_from, turns_complete, parallel?, state) do
    state = %{state | turns_complete: turns_complete}
    wait_for_objects? = state.opts[:wait_for_objects] == true

    if parallel? do
      # In parallel mode, wait for all agents
      all_complete? = Enum.all?(state.agent_names, &MapSet.member?(turns_complete, &1))

      if all_complete? do
        state = %{state | turns_complete: MapSet.new()}

        if wait_for_objects? do
          # Schedule a delayed check for pending objects
          # This gives objects time to send their busy signals (500ms should be enough)
          Logger.debug("[Tick] Turn complete, waiting for objects (check in 500ms)")
          Process.send_after(self(), :check_objects_ready, 500)
          {:noreply, %{state | turn_waiting_for_objects: true}}
        else
          # Signal metrics to collect states, then wait for step_complete
          {:send, :metrics, encode_round_complete(state.current_step), state}
        end
      else
        {:noreply, state}
      end
    else
      # Sequential mode: advance to next agent
      next_index = state.turn_index + 1

      if next_index >= length(state.agent_names) do
        state = %{state | turn_index: 0, turns_complete: MapSet.new()}

        if wait_for_objects? do
          # Schedule a delayed check for pending objects
          # This gives objects time to send their busy signals (500ms should be enough)
          Logger.debug("[Tick] Turn complete, waiting for objects (check in 500ms)")
          Process.send_after(self(), :check_objects_ready, 500)
          {:noreply, %{state | turn_waiting_for_objects: true}}
        else
          # Round complete, signal metrics
          {:send, :metrics, encode_round_complete(state.current_step), state}
        end
      else
        # Send your_turn to next agent
        state = %{state | turn_index: next_index}
        next_agent = Enum.at(state.agent_names, next_index)
        Logger.debug("[Tick] Sending your_turn to #{next_agent} (step=#{state.current_step})")
        {:send, next_agent, encode_your_turn(state.current_step), state}
      end
    end
  end

  # Called when all objects are ready after waiting
  defp do_advance_after_turn(state) do
    # Signal metrics that round is complete
    {:send, :metrics, encode_round_complete(state.current_step), state}
  end

  defp handle_step_complete(state) do
    # Check max steps
    if state.max_steps && state.current_step >= state.max_steps do
      state = %{state | halted: true}
      RuntimeStore.set_status(state.sim_name, :completed)
      Logger.info("[Tick] Simulation #{state.sim_name} completed: max_steps reached")
      {:broadcast, encode_halt("max_steps", state.current_step), state}
    else
      state = advance_step(state)

      case state.mode do
        :turn_based ->
          # Start new round
          state = %{state | turn_index: 0}

          if state.opts[:parallel] do
            # Broadcast your_turn to all agents
            {:broadcast, encode_your_turn(state.current_step), state}
          else
            # Send to first agent
            first_agent = Enum.at(state.agent_names, 0)
            {:send, first_agent, encode_your_turn(state.current_step), state}
          end

        _ ->
          {:broadcast, encode_new_step(state.current_step), state}
      end
    end
  end

  defp advance_step(state) do
    new_step = state.current_step + 1
    RuntimeStore.set_step(state.sim_name, new_step)
    %{state | current_step: new_step}
  end

  defp schedule_time_tick(state) do
    interval_seconds = state.opts[:every] || 60
    Process.send_after(self(), :time_tick, interval_seconds * 1000)
  end

  defp schedule_ipc_check do
    # Poll for IPC commands every 500ms
    Process.send_after(self(), :check_ipc, 500)
  end

  # Check for pause/resume requests via DETS IPC
  defp check_ipc_commands(state) do
    cond do
      not state.paused and RuntimeStore.consume_pause_request(state.sim_name) ->
        Logger.info("[Tick] Simulation #{state.sim_name} paused at step #{state.current_step} (via IPC)")
        RuntimeStore.set_paused(state.sim_name, state.current_step)
        %{state | paused: true}

      state.paused and RuntimeStore.consume_resume_request(state.sim_name) ->
        Logger.info("[Tick] Simulation #{state.sim_name} resumed at step #{state.current_step} (via IPC)")
        RuntimeStore.clear_paused(state.sim_name)
        %{state | paused: false}

      true ->
        state
    end
  end

  # Message encoding

  defp encode_new_step(step) do
    Jason.encode!(%{action: "new_step", data: %{step: step}})
  end

  defp encode_your_turn(step) do
    Jason.encode!(%{action: "your_turn", data: %{step: step}})
  end

  defp encode_round_complete(step) do
    Jason.encode!(%{action: "round_complete", data: %{step: step}})
  end

  defp encode_halt(reason, step) do
    Jason.encode!(%{action: "simulation_halted", data: %{reason: reason, step: step}})
  end

  defp encode_start_step(step) do
    Jason.encode!(%{action: "start_step", data: %{step: step}})
  end

  defp encode_start_turn(step) do
    Jason.encode!(%{action: "start_turn", data: %{step: step}})
  end

  defp encode_simulation_started(step) do
    Jason.encode!(%{action: "simulation_started", data: %{step: step}})
  end

  defp encode_paused(step) do
    Jason.encode!(%{action: "simulation_paused", data: %{step: step}})
  end

  defp encode_resumed(step) do
    Jason.encode!(%{action: "simulation_resumed", data: %{step: step}})
  end
end
