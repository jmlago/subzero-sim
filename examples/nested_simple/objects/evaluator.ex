defmodule NestedSimple.Objects.Evaluator do
  @moduledoc """
  Object that launches a child simulation and collects its result.

  This demonstrates the nested simulation pattern where a parent
  simulation can spawn and manage child simulations.

  Supports `wait_for_objects` mode by sending `object_busy` before
  starting the child and `object_ready` when done.
  """

  @behaviour Genswarms.Objects.ObjectHandler

  require Logger

  def init(config) do
    {:ok, %{
      child_sim: config[:child_sim],
      result: nil,
      swarm_name: config[:swarm_name],
      child_count: 0,
      processing: false  # Debounce flag
    }}
  end

  def interface do
    %{
      evaluate: %{
        input: ~s({"action": "evaluate"}),
        output: ~s({"result": {...}})
      }
    }
  end

  def handle_message(from, content, state) do
    case Jason.decode(content) do
      {:ok, %{"action" => "evaluate"}} ->
        # Debounce: ignore if already processing
        if state.processing do
          Logger.debug("[Evaluator] Ignoring duplicate evaluate request (already processing)")
          {:noreply, state}
        else
          Logger.info("[Evaluator] Received evaluate request from #{from}")
          state = %{state | processing: true}
          run_child_simulation(from, state)
        end

      {:ok, msg} ->
        Logger.debug("[Evaluator] Ignoring message from #{from}: #{inspect(msg)}")
        {:noreply, state}

      {:error, _} ->
        Logger.warning("[Evaluator] Invalid JSON from #{from}: #{content}")
        {:noreply, state}
    end
  end

  defp run_child_simulation(from, state) do
    # Signal that we're starting long-running work BEFORE blocking
    # Use Router directly so it's sent immediately, not after we return
    alias Genswarms.Routing.Router
    busy_msg = Jason.encode!(%{action: "object_busy"})
    Router.route(state.swarm_name, :evaluator, :tick, busy_msg)
    Logger.info("[Evaluator] Signaled object_busy to tick")

    case SubzeroSim.Loader.load(state.child_sim) do
      {:ok, spec} ->
        # Generate unique child name to avoid conflicts
        child_count = state.child_count + 1
        spec = %{spec | name: "#{spec.name}_#{child_count}"}
        state = %{state | child_count: child_count}

        Logger.info("[Evaluator] Launching child simulation: #{spec.name}")

        case SubzeroSim.Runner.start_child(spec,
               collect_from: :coordinator,
               initial_task: %{task: "do_work"}
             ) do
          {:ok, child} ->
            Logger.info("[Evaluator] Waiting for child simulation: #{child.name}")

            case SubzeroSim.Runner.wait_for_completion(child.name) do
              {:ok, info} ->
                result = Map.get(info, :gateway_result, %{})
                Logger.info("[Evaluator] Child completed with result: #{inspect(result)}")
                response = Jason.encode!(%{result: result, metrics: info.metrics})
                ready_msg = Jason.encode!(%{action: "object_ready"})
                # Send ready to tick, then reply to requester
                # Reset processing flag so we can handle next request
                {:multi, [{:send, :tick, ready_msg}, {:send, from, response}], %{state | result: result, processing: false}}

              {:error, reason} ->
                Logger.error("[Evaluator] Child failed: #{inspect(reason)}")
                response = Jason.encode!(%{error: "Child simulation failed", reason: inspect(reason)})
                ready_msg = Jason.encode!(%{action: "object_ready"})
                {:multi, [{:send, :tick, ready_msg}, {:send, from, response}], %{state | processing: false}}
            end

          {:error, reason} ->
            Logger.error("[Evaluator] Failed to start child: #{inspect(reason)}")
            response = Jason.encode!(%{error: "Failed to start child", reason: inspect(reason)})
            ready_msg = Jason.encode!(%{action: "object_ready"})
            {:multi, [{:send, :tick, ready_msg}, {:send, from, response}], %{state | processing: false}}
        end

      {:error, reason} ->
        Logger.error("[Evaluator] Failed to load child sim: #{inspect(reason)}")
        response = Jason.encode!(%{error: "Failed to load simulation", reason: inspect(reason)})
        {:reply, response, %{state | processing: false}}
    end
  end
end
