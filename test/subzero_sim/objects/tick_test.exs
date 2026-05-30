defmodule SubzeroSim.Objects.TickTest do
  use ExUnit.Case, async: false

  alias SubzeroSim.Objects.Tick
  alias SubzeroSim.Store.RuntimeStore

  setup do
    # Clean up any previous state
    RuntimeStore.ensure_table()
    RuntimeStore.cleanup("test_sim")
    :ok
  end

  # Helper to extract state from init result (handles both {:ok, state} and {:ok, state, action})
  defp extract_state({:ok, state}), do: state
  defp extract_state({:ok, state, _action}), do: state

  describe "init/1" do
    test "initializes with default config" do
      config = %{
        sim_name: "test_sim",
        agent_names: [:agent_1, :agent_2]
      }

      result = Tick.init(config)
      state = extract_state(result)
      assert state.sim_name == "test_sim"
      assert state.mode == :state_reports
      assert state.agent_names == [:agent_1, :agent_2]
      assert state.started == true  # :immediate trigger
      assert state.current_step == 1
    end

    test "initializes with turn_based mode and sends your_turn to first agent" do
      config = %{
        sim_name: "test_sim",
        mode: :turn_based,
        opts: %{parallel: false},
        agent_names: [:a, :b]
      }

      assert {:ok, state, {:send, :a, msg}} = Tick.init(config)
      assert state.mode == :turn_based
      assert state.opts == %{parallel: false}
      assert %{"action" => "your_turn"} = Jason.decode!(msg)
    end

    test "initializes with turn_based parallel mode" do
      config = %{
        sim_name: "test_sim",
        mode: :turn_based,
        opts: %{parallel: true},
        agent_names: [:a, :b]
      }

      # Parallel mode sends start_turn to metrics which will broadcast
      assert {:ok, state, {:send, :metrics, msg}} = Tick.init(config)
      assert state.mode == :turn_based
      assert state.opts == %{parallel: true}
      assert %{"action" => "start_turn"} = Jason.decode!(msg)
    end

    test "initializes with on_ready trigger" do
      config = %{
        sim_name: "test_sim",
        start_trigger: :on_ready,
        agent_names: [:a]
      }

      assert {:ok, state} = Tick.init(config)
      assert state.started == false
      assert state.current_step == 0
    end

    test "initializes with manual trigger" do
      config = %{
        sim_name: "test_sim",
        start_trigger: :manual,
        agent_names: [:a]
      }

      assert {:ok, state} = Tick.init(config)
      assert state.started == false
    end

    test "sets up runtime store" do
      config = %{
        sim_name: "test_sim",
        agent_names: [:a]
      }

      Tick.init(config)

      assert RuntimeStore.get_status("test_sim") == :running
      assert RuntimeStore.get_step("test_sim") == 1
    end
  end

  describe "handle_message/3 - state_reports mode" do
    setup do
      config = %{
        sim_name: "test_sim",
        mode: :state_reports,
        agent_names: [:agent_1, :agent_2],
        max_steps: 10
      }

      state = extract_state(Tick.init(config))
      {:ok, state: state}
    end

    test "advances step on step_complete", %{state: state} do
      msg = Jason.encode!(%{action: "step_complete"})
      {:broadcast, response, new_state} = Tick.handle_message(:metrics, msg, state)

      assert new_state.current_step == 2
      assert %{"action" => "new_step", "data" => %{"step" => 2}} = Jason.decode!(response)
    end

    test "halts on max_steps reached", %{state: state} do
      state = %{state | current_step: 10}
      msg = Jason.encode!(%{action: "step_complete"})
      {:broadcast, response, new_state} = Tick.handle_message(:metrics, msg, state)

      assert new_state.halted == true
      assert %{"action" => "simulation_halted", "data" => %{"reason" => "max_steps"}} =
               Jason.decode!(response)
    end

    test "handles halt message from metrics", %{state: state} do
      msg = Jason.encode!(%{action: "halt", data: %{reason: "predicate_met"}})
      {:broadcast, response, new_state} = Tick.handle_message(:metrics, msg, state)

      assert new_state.halted == true
      assert %{"action" => "simulation_halted", "data" => %{"reason" => "predicate_met"}} =
               Jason.decode!(response)
    end
  end

  describe "handle_message/3 - turn_based sequential mode" do
    setup do
      config = %{
        sim_name: "test_sim",
        mode: :turn_based,
        opts: %{parallel: false},
        agent_names: [:agent_1, :agent_2, :agent_3],
        max_steps: 10
      }

      state = extract_state(Tick.init(config))
      {:ok, state: state}
    end

    test "advances to next agent on turn_complete", %{state: state} do
      # First agent completes turn
      msg = Jason.encode!(%{action: "turn_complete"})
      {:send, to, response, new_state} = Tick.handle_message(:agent_1, msg, state)

      assert to == :agent_2
      assert new_state.turn_index == 1
      assert %{"action" => "your_turn", "data" => %{"step" => 1}} = Jason.decode!(response)
    end

    test "signals metrics when all agents complete round", %{state: state} do
      # Simulate all agents completing
      state = %{state | turn_index: 2, turns_complete: MapSet.new([:agent_1, :agent_2])}
      msg = Jason.encode!(%{action: "turn_complete"})
      {:send, to, response, new_state} = Tick.handle_message(:agent_3, msg, state)

      assert to == :metrics
      assert new_state.turn_index == 0
      assert MapSet.size(new_state.turns_complete) == 0
      assert %{"action" => "round_complete"} = Jason.decode!(response)
    end
  end

  describe "handle_message/3 - turn_based parallel mode" do
    setup do
      config = %{
        sim_name: "test_sim",
        mode: :turn_based,
        opts: %{parallel: true},
        agent_names: [:agent_1, :agent_2],
        max_steps: 10
      }

      state = extract_state(Tick.init(config))
      {:ok, state: state}
    end

    test "waits for all agents in parallel mode", %{state: state} do
      msg = Jason.encode!(%{action: "turn_complete"})

      # First agent completes
      {:noreply, state} = Tick.handle_message(:agent_1, msg, state)
      assert MapSet.member?(state.turns_complete, :agent_1)

      # Second agent completes - should signal metrics
      {:send, to, _response, new_state} = Tick.handle_message(:agent_2, msg, state)
      assert to == :metrics
      assert MapSet.size(new_state.turns_complete) == 0
    end
  end

  describe "handle_message/3 - output_count mode" do
    setup do
      config = %{
        sim_name: "test_sim",
        mode: :output_count,
        opts: %{every: 5},
        agent_names: [:agent_1, :agent_2],
        max_steps: 10
      }

      state = extract_state(Tick.init(config))
      {:ok, state: state}
    end

    test "counts outputs and advances step when threshold reached", %{state: state} do
      msg = Jason.encode!(%{action: "output_reported", data: %{count: 3}})

      # First report: 3 outputs
      {:noreply, state} = Tick.handle_message(:agent_1, msg, state)
      assert state.output_count == 3

      # Second report: 3 more, total 6 >= 5 threshold
      {:broadcast, response, new_state} = Tick.handle_message(:agent_2, msg, state)
      assert new_state.output_count == 0
      assert new_state.current_step == 2
      assert %{"action" => "new_step"} = Jason.decode!(response)
    end
  end

  describe "handle_message/3 - on_ready trigger" do
    setup do
      config = %{
        sim_name: "test_sim",
        start_trigger: :on_ready,
        agent_names: [:agent_1, :agent_2]
      }

      state = extract_state(Tick.init(config))
      {:ok, state: state}
    end

    test "starts when all agents ready", %{state: state} do
      msg = Jason.encode!(%{action: "agent_ready"})

      # First agent ready
      {:noreply, state} = Tick.handle_message(:agent_1, msg, state)
      assert not state.started
      assert MapSet.member?(state.agents_ready, :agent_1)

      # Second agent ready - should start and broadcast
      {:broadcast, _response, new_state} = Tick.handle_message(:agent_2, msg, state)
      assert new_state.started == true
      assert new_state.current_step == 1
    end
  end

  describe "handle_message/3 - manual trigger" do
    setup do
      config = %{
        sim_name: "test_sim",
        start_trigger: :manual,
        agent_names: [:agent_1]
      }

      state = extract_state(Tick.init(config))
      {:ok, state: state}
    end

    test "starts on start message", %{state: state} do
      msg = Jason.encode!(%{action: "start"})
      {:broadcast, _response, new_state} = Tick.handle_message(:external, msg, state)

      assert new_state.started == true
      assert new_state.current_step == 1
    end

    test "ignores start if already started", %{state: state} do
      state = %{state | started: true}
      msg = Jason.encode!(%{action: "start"})
      {:noreply, new_state} = Tick.handle_message(:external, msg, state)

      assert new_state == state
    end
  end

  describe "interface/0" do
    test "returns interface schema" do
      interface = Tick.interface()
      assert Map.has_key?(interface, :new_step)
      assert Map.has_key?(interface, :your_turn)
      assert Map.has_key?(interface, :turn_complete)
    end
  end
end
