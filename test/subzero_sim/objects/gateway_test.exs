defmodule SubzeroSim.Objects.GatewayTest do
  use ExUnit.Case, async: true

  alias SubzeroSim.Objects.Gateway

  describe "init/1" do
    test "initializes with config" do
      config = %{
        sim_name: "test_sim",
        parent_pid: self(),
        inject_to: :coordinator,
        collect_from: :coordinator,
        initial_task: %{task: "do_work"}
      }

      assert {:ok, state} = Gateway.init(config)
      assert state.sim_name == "test_sim"
      assert state.parent_pid == self()
      assert state.inject_to == :coordinator
      assert state.collect_from == :coordinator
      assert state.initial_task == %{task: "do_work"}
      assert state.result == nil
      assert state.task_injected == false
    end

    test "initializes with minimal config" do
      config = %{sim_name: "minimal_sim"}

      assert {:ok, state} = Gateway.init(config)
      assert state.sim_name == "minimal_sim"
      assert state.inject_to == nil
      assert state.collect_from == nil
    end
  end

  describe "handle_message - simulation_started" do
    test "injects initial_task to inject_to agent" do
      {:ok, state} =
        Gateway.init(%{
          sim_name: "test",
          inject_to: :coordinator,
          initial_task: %{task: "work"}
        })

      msg = Jason.encode!(%{action: "simulation_started", data: %{step: 1}})

      assert {:send, :coordinator, response, new_state} =
               Gateway.handle_message(:tick, msg, state)

      assert new_state.task_injected == true
      assert %{"action" => "initial_task", "data" => %{"task" => "work"}} = Jason.decode!(response)
    end

    test "does not inject if already injected" do
      {:ok, state} =
        Gateway.init(%{
          sim_name: "test",
          inject_to: :coordinator,
          initial_task: %{task: "work"}
        })

      state = %{state | task_injected: true}
      msg = Jason.encode!(%{action: "simulation_started", data: %{step: 1}})

      assert {:noreply, ^state} = Gateway.handle_message(:tick, msg, state)
    end

    test "does not inject if no inject_to specified" do
      {:ok, state} = Gateway.init(%{sim_name: "test", initial_task: %{task: "work"}})
      msg = Jason.encode!(%{action: "simulation_started", data: %{step: 1}})

      assert {:noreply, _state} = Gateway.handle_message(:tick, msg, state)
    end

    test "does not inject if no initial_task specified" do
      {:ok, state} = Gateway.init(%{sim_name: "test", inject_to: :coordinator})
      msg = Jason.encode!(%{action: "simulation_started", data: %{step: 1}})

      assert {:noreply, _state} = Gateway.handle_message(:tick, msg, state)
    end
  end

  describe "handle_message - final_result" do
    test "accepts final_result from collect_from agent" do
      parent = self()

      {:ok, state} =
        Gateway.init(%{
          sim_name: "test",
          parent_pid: parent,
          collect_from: :coordinator
        })

      msg = Jason.encode!(%{action: "final_result", data: %{output: 42}})

      assert {:noreply, new_state} = Gateway.handle_message(:coordinator, msg, state)
      assert new_state.result == %{"output" => 42}

      # Verify parent was notified
      assert_receive {:gateway_result, "test", %{"output" => 42}}
    end

    test "accepts final_result from expanded agent name" do
      parent = self()

      {:ok, state} =
        Gateway.init(%{
          sim_name: "test",
          parent_pid: parent,
          collect_from: :coordinator
        })

      msg = Jason.encode!(%{action: "final_result", data: %{output: 42}})

      # coordinator_1 should match :coordinator
      assert {:noreply, new_state} = Gateway.handle_message(:coordinator_1, msg, state)
      assert new_state.result == %{"output" => 42}
    end

    test "ignores final_result from wrong agent when collect_from is set" do
      {:ok, state} =
        Gateway.init(%{
          sim_name: "test",
          collect_from: :coordinator
        })

      msg = Jason.encode!(%{action: "final_result", data: %{output: 42}})

      assert {:noreply, new_state} = Gateway.handle_message(:other_agent, msg, state)
      assert new_state.result == nil
    end

    test "accepts final_result from any agent when collect_from is nil" do
      parent = self()

      {:ok, state} =
        Gateway.init(%{
          sim_name: "test",
          parent_pid: parent,
          collect_from: nil
        })

      msg = Jason.encode!(%{action: "final_result", data: %{output: 42}})

      assert {:noreply, new_state} = Gateway.handle_message(:any_agent, msg, state)
      assert new_state.result == %{"output" => 42}
    end
  end

  describe "interface/0" do
    test "returns interface spec" do
      interface = Gateway.interface()
      assert is_map(interface)
      assert Map.has_key?(interface, :simulation_started)
      assert Map.has_key?(interface, :final_result)
    end
  end
end
