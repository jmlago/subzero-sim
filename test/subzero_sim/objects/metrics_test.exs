defmodule SubzeroSim.Objects.MetricsTest do
  use ExUnit.Case, async: false

  alias SubzeroSim.Objects.Metrics
  alias SubzeroSim.Store.{MetricsStore, StateStore}
  alias SubzeroSim.Spec.{MeasureSpec, HaltCondition}

  setup do
    # Clean up stores using DETS-compatible cleanup
    MetricsStore.ensure_table()
    StateStore.ensure_table()

    # Clean up test data (use cleanup function for each test sim)
    for sim <- ["test_sim", "converge_test", "plateau_test", "history_test"] do
      MetricsStore.cleanup(sim)
      StateStore.cleanup(sim)
    end
    :ok
  end

  describe "init/1" do
    test "initializes with config" do
      config = %{
        sim_name: "test_sim",
        agent_names: [:agent_1, :agent_2],
        measures: [],
        halt_conditions: []
      }

      assert {:ok, state} = Metrics.init(config)
      assert state.sim_name == "test_sim"
      assert state.agent_names == [:agent_1, :agent_2]
      assert state.pending_states == MapSet.new()
    end
  end

  describe "handle_message/3 - state_report" do
    setup do
      measure = %MeasureSpec{
        name: :total,
        function: fn states ->
          states
          |> Map.values()
          |> Enum.map(fn s -> Map.get(s, "value", 0) end)
          |> Enum.sum()
        end,
        every: 1
      }

      config = %{
        sim_name: "test_sim",
        agent_names: [:agent_1, :agent_2],
        measures: [measure],
        halt_conditions: []
      }

      {:ok, state} = Metrics.init(config)
      state = %{state | current_step: 1}
      {:ok, state: state, measure: measure}
    end

    test "collects state from first agent", %{state: state} do
      msg = Jason.encode!(%{action: "state_report", data: %{state: %{value: 10}}})
      {:noreply, new_state} = Metrics.handle_message(:agent_1, msg, state)

      assert MapSet.member?(new_state.pending_states, :agent_1)
      assert StateStore.get("test_sim", :agent_1, 1) == %{"value" => 10}
    end

    test "computes metrics when all agents report", %{state: state} do
      # First agent reports
      msg1 = Jason.encode!(%{action: "state_report", data: %{state: %{value: 10}}})
      {:noreply, state} = Metrics.handle_message(:agent_1, msg1, state)

      # Second agent reports - should complete step
      msg2 = Jason.encode!(%{action: "state_report", data: %{state: %{value: 20}}})
      {:send, to, _response, _new_state} = Metrics.handle_message(:agent_2, msg2, state)

      assert to == :tick
      assert MetricsStore.get("test_sim", :total, 1) == 30
    end

    test "signals step_complete to tick", %{state: state} do
      msg1 = Jason.encode!(%{action: "state_report", data: %{state: %{}}})
      {:noreply, state} = Metrics.handle_message(:agent_1, msg1, state)

      msg2 = Jason.encode!(%{action: "state_report", data: %{state: %{}}})
      {:send, to, response, _state} = Metrics.handle_message(:agent_2, msg2, state)

      assert to == :tick
      assert %{"action" => "step_complete"} = Jason.decode!(response)
    end
  end

  describe "handle_message/3 - halt conditions" do
    test "triggers halt on after_steps condition" do
      halt = HaltCondition.after_steps(5)

      config = %{
        sim_name: "test_sim",
        agent_names: [:agent_1],
        measures: [],
        halt_conditions: [halt]
      }

      {:ok, state} = Metrics.init(config)
      state = %{state | current_step: 5}

      msg = Jason.encode!(%{action: "state_report", data: %{state: %{}}})
      {:send, to, response, _state} = Metrics.handle_message(:agent_1, msg, state)

      assert to == :tick
      assert %{"action" => "halt", "data" => %{"reason" => "after_5_steps"}} = Jason.decode!(response)
    end

    test "triggers halt on predicate condition" do
      measure = %MeasureSpec{
        name: :count,
        function: fn states -> map_size(states) end,
        every: 1
      }

      halt = HaltCondition.when_predicate(fn metrics -> metrics[:count] >= 1 end)

      config = %{
        sim_name: "test_sim",
        agent_names: [:agent_1],
        measures: [measure],
        halt_conditions: [halt]
      }

      {:ok, state} = Metrics.init(config)
      state = %{state | current_step: 1}

      msg = Jason.encode!(%{action: "state_report", data: %{state: %{}}})
      {:send, to, response, _state} = Metrics.handle_message(:agent_1, msg, state)

      assert to == :tick
      assert %{"action" => "halt", "data" => %{"reason" => "predicate_met"}} = Jason.decode!(response)
    end

    test "continues when halt condition not met" do
      halt = HaltCondition.after_steps(10)

      config = %{
        sim_name: "test_sim",
        agent_names: [:agent_1],
        measures: [],
        halt_conditions: [halt]
      }

      {:ok, state} = Metrics.init(config)
      state = %{state | current_step: 1}

      msg = Jason.encode!(%{action: "state_report", data: %{state: %{}}})
      {:send, to, response, _state} = Metrics.handle_message(:agent_1, msg, state)

      assert to == :tick
      assert %{"action" => "step_complete"} = Jason.decode!(response)
    end

    test "triggers halt on metric_converged condition" do
      measure = %MeasureSpec{
        name: :wealth,
        function: fn _states -> 1000 end,  # Always returns same value
        every: 1
      }

      halt = HaltCondition.metric_converged(:wealth, threshold: 10, window: 5)

      config = %{
        sim_name: "converge_test",
        agent_names: [:agent_1],
        measures: [measure],
        halt_conditions: [halt]
      }

      {:ok, state} = Metrics.init(config)

      # Simulate 5 steps with same value to create convergence
      msg = Jason.encode!(%{action: "state_report", data: %{state: %{}}})

      state = %{state | current_step: 1}
      {:send, :tick, _, state} = Metrics.handle_message(:agent_1, msg, state)

      state = %{state | current_step: 2, pending_states: MapSet.new()}
      {:send, :tick, _, state} = Metrics.handle_message(:agent_1, msg, state)

      state = %{state | current_step: 3, pending_states: MapSet.new()}
      {:send, :tick, _, state} = Metrics.handle_message(:agent_1, msg, state)

      state = %{state | current_step: 4, pending_states: MapSet.new()}
      {:send, :tick, _, state} = Metrics.handle_message(:agent_1, msg, state)

      # Step 5 should trigger convergence (5 steps with same value, range < 10)
      state = %{state | current_step: 5, pending_states: MapSet.new()}
      {:send, to, response, _state} = Metrics.handle_message(:agent_1, msg, state)

      assert to == :tick
      assert %{"action" => "halt", "data" => %{"reason" => "wealth_converged"}} = Jason.decode!(response)
    end

    test "triggers halt on metric_plateaued condition" do
      # Wealth changes by 1 each step (less than threshold of 5)
      step_counter = :counters.new(1, [:atomics])

      measure = %MeasureSpec{
        name: :wealth,
        function: fn _states ->
          :counters.add(step_counter, 1, 1)
          :counters.get(step_counter, 1) * 1  # increases by 1 each time
        end,
        every: 1
      }

      halt = HaltCondition.metric_plateaued(:wealth, threshold: 5, window: 3)

      config = %{
        sim_name: "plateau_test",
        agent_names: [:agent_1],
        measures: [measure],
        halt_conditions: [halt]
      }

      {:ok, state} = Metrics.init(config)

      msg = Jason.encode!(%{action: "state_report", data: %{state: %{}}})

      # Run 3 steps - change of 1 per step is below threshold of 5
      state = %{state | current_step: 1}
      {:send, :tick, _, state} = Metrics.handle_message(:agent_1, msg, state)

      state = %{state | current_step: 2, pending_states: MapSet.new()}
      {:send, :tick, _, state} = Metrics.handle_message(:agent_1, msg, state)

      # Step 3 should trigger plateau (avg change of 1 < threshold of 5)
      state = %{state | current_step: 3, pending_states: MapSet.new()}
      {:send, to, response, _state} = Metrics.handle_message(:agent_1, msg, state)

      assert to == :tick
      assert %{"action" => "halt", "data" => %{"reason" => "wealth_plateaued"}} = Jason.decode!(response)
    end

    test "triggers halt on when_history condition" do
      measure = %MeasureSpec{
        name: :value,
        function: fn _states -> 42 end,
        every: 1
      }

      halt = HaltCondition.when_history(fn {_metrics, history} ->
        case history[:value] do
          series when length(series) >= 3 -> true
          _ -> false
        end
      end)

      config = %{
        sim_name: "history_test",
        agent_names: [:agent_1],
        measures: [measure],
        halt_conditions: [halt]
      }

      {:ok, state} = Metrics.init(config)

      msg = Jason.encode!(%{action: "state_report", data: %{state: %{}}})

      state = %{state | current_step: 1}
      {:send, :tick, _, state} = Metrics.handle_message(:agent_1, msg, state)

      state = %{state | current_step: 2, pending_states: MapSet.new()}
      {:send, :tick, _, state} = Metrics.handle_message(:agent_1, msg, state)

      # Step 3 should trigger (history has 3 entries)
      state = %{state | current_step: 3, pending_states: MapSet.new()}
      {:send, to, response, _state} = Metrics.handle_message(:agent_1, msg, state)

      assert to == :tick
      assert %{"action" => "halt", "data" => %{"reason" => "history_predicate_met"}} = Jason.decode!(response)
    end
  end

  describe "handle_message/3 - round_complete (turn_based)" do
    test "requests states from all agents" do
      config = %{
        sim_name: "test_sim",
        agent_names: [:agent_1, :agent_2],
        measures: [],
        halt_conditions: []
      }

      {:ok, state} = Metrics.init(config)

      msg = Jason.encode!(%{action: "round_complete", data: %{step: 5}})
      {:broadcast, response, new_state} = Metrics.handle_message(:tick, msg, state)

      assert new_state.current_step == 5
      assert %{"action" => "request_state", "data" => %{"step" => 5}} = Jason.decode!(response)
    end
  end

  describe "handle_message/3 - query" do
    test "returns metric value" do
      config = %{
        sim_name: "test_sim",
        agent_names: [],
        measures: [],
        halt_conditions: []
      }

      {:ok, state} = Metrics.init(config)

      # Store a metric
      MetricsStore.put("test_sim", :test_metric, 1, 42)

      msg = Jason.encode!(%{action: "query", data: %{metric: "test_metric"}})
      {:reply, response, _state} = Metrics.handle_message(:external, msg, state)

      assert %{"metric" => "test_metric", "value" => 42, "step" => 1} = Jason.decode!(response)
    end

    test "returns all metrics" do
      config = %{
        sim_name: "test_sim",
        agent_names: [],
        measures: [],
        halt_conditions: []
      }

      {:ok, state} = Metrics.init(config)
      state = %{state | current_step: 1}

      MetricsStore.put("test_sim", :metric_a, 1, 10)
      MetricsStore.put("test_sim", :metric_b, 1, 20)

      msg = Jason.encode!(%{action: "query", data: %{all: true}})
      {:reply, response, _state} = Metrics.handle_message(:external, msg, state)

      decoded = Jason.decode!(response)
      assert decoded["metrics"]["metric_a"] == 10
      assert decoded["metrics"]["metric_b"] == 20
    end

    test "returns error for unknown metric" do
      config = %{
        sim_name: "test_sim",
        agent_names: [],
        measures: [],
        halt_conditions: []
      }

      {:ok, state} = Metrics.init(config)

      msg = Jason.encode!(%{action: "query", data: %{metric: "nonexistent"}})
      {:reply, response, _state} = Metrics.handle_message(:external, msg, state)

      assert %{"error" => _} = Jason.decode!(response)
    end
  end

  describe "metric computation with every option" do
    test "only computes metrics at specified intervals" do
      measure = %MeasureSpec{
        name: :expensive,
        function: fn _states -> :computed end,
        every: 5
      }

      config = %{
        sim_name: "test_sim",
        agent_names: [:agent_1],
        measures: [measure],
        halt_conditions: []
      }

      {:ok, state} = Metrics.init(config)

      # Step 1 - should not compute (1 % 5 != 0)
      state = %{state | current_step: 1}
      msg = Jason.encode!(%{action: "state_report", data: %{state: %{}}})
      {:send, :tick, _, state} = Metrics.handle_message(:agent_1, msg, state)

      assert MetricsStore.get("test_sim", :expensive, 1) == nil

      # Step 5 - should compute (5 % 5 == 0)
      state = %{state | current_step: 5, pending_states: MapSet.new()}
      {:send, :tick, _, _state} = Metrics.handle_message(:agent_1, msg, state)

      assert MetricsStore.get("test_sim", :expensive, 5) == :computed
    end
  end

  describe "interface/0" do
    test "returns interface schema" do
      interface = Metrics.interface()
      assert Map.has_key?(interface, :state_report)
      assert Map.has_key?(interface, :query)
    end
  end
end
