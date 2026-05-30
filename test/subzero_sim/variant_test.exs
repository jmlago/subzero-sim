defmodule SubzeroSim.VariantTest do
  use ExUnit.Case, async: true

  alias SubzeroSim.Variant
  alias SubzeroSim.Spec.{SimSpec, RoleSpec, TickConfig, Connection}

  setup do
    spec = %SimSpec{
      name: "test_sim",
      roles: [
        %RoleSpec{name: :worker, count: 2, backend: :bwrap, model: "gpt-4", config: %{speed: 1}},
        %RoleSpec{name: :manager, count: 1, backend: :bwrap}
      ],
      connections: [%Connection{from: :worker, to: :manager, bidirectional: false}],
      tick_config: %TickConfig{mode: :state_reports},
      steps: 10
    }

    {:ok, spec: spec}
  end

  describe "set_name/2" do
    test "sets simulation name", %{spec: spec} do
      result = Variant.set_name(spec, "new_name")
      assert result.name == "new_name"
    end
  end

  describe "set_agent_count/3" do
    test "sets count for existing role", %{spec: spec} do
      result = Variant.set_agent_count(spec, :worker, 5)
      worker = Enum.find(result.roles, &(&1.name == :worker))
      assert worker.count == 5
    end

    test "does not affect other roles", %{spec: spec} do
      result = Variant.set_agent_count(spec, :worker, 5)
      manager = Enum.find(result.roles, &(&1.name == :manager))
      assert manager.count == 1
    end

    test "handles non-existent role gracefully", %{spec: spec} do
      result = Variant.set_agent_count(spec, :nonexistent, 5)
      # Should not crash, roles unchanged
      assert result.roles == spec.roles
    end
  end

  describe "set_model/3" do
    test "sets model for role", %{spec: spec} do
      result = Variant.set_model(spec, :worker, "claude-3-opus")
      worker = Enum.find(result.roles, &(&1.name == :worker))
      assert worker.model == "claude-3-opus"
    end
  end

  describe "set_backend/3" do
    test "sets backend for role", %{spec: spec} do
      result = Variant.set_backend(spec, :worker, :openai)
      worker = Enum.find(result.roles, &(&1.name == :worker))
      assert worker.backend == :openai
    end
  end

  describe "update_config/3" do
    test "merges config updates", %{spec: spec} do
      result = Variant.update_config(spec, :worker, %{power: 100})
      worker = Enum.find(result.roles, &(&1.name == :worker))
      assert worker.config == %{speed: 1, power: 100}
    end

    test "overwrites existing keys", %{spec: spec} do
      result = Variant.update_config(spec, :worker, %{speed: 5})
      worker = Enum.find(result.roles, &(&1.name == :worker))
      assert worker.config == %{speed: 5}
    end
  end

  describe "set_config/3" do
    test "replaces entire config", %{spec: spec} do
      result = Variant.set_config(spec, :worker, %{new_key: "value"})
      worker = Enum.find(result.roles, &(&1.name == :worker))
      assert worker.config == %{new_key: "value"}
    end
  end

  describe "set_skill/3" do
    test "sets skill path for role", %{spec: spec} do
      result = Variant.set_skill(spec, :worker, "skills/new_worker.md")
      worker = Enum.find(result.roles, &(&1.name == :worker))
      assert worker.skill == "skills/new_worker.md"
    end
  end

  describe "add_connection/3" do
    test "adds unidirectional connection", %{spec: spec} do
      result = Variant.add_connection(spec, :manager, :worker)
      assert length(result.connections) == 2
      new_conn = List.last(result.connections)
      assert new_conn.from == :manager
      assert new_conn.to == :worker
      assert new_conn.bidirectional == false
    end

    test "adds bidirectional connection", %{spec: spec} do
      result = Variant.add_connection(spec, :manager, :worker, bidirectional: true)
      new_conn = List.last(result.connections)
      assert new_conn.bidirectional == true
    end
  end

  describe "remove_connection/3" do
    test "removes connection", %{spec: spec} do
      result = Variant.remove_connection(spec, :worker, :manager)
      assert Enum.empty?(result.connections)
    end
  end

  describe "set_steps/2" do
    test "sets max steps", %{spec: spec} do
      result = Variant.set_steps(spec, 100)
      assert result.steps == 100
    end

    test "sets steps to nil", %{spec: spec} do
      result = Variant.set_steps(spec, nil)
      assert result.steps == nil
    end
  end

  describe "set_tick_mode/3" do
    test "sets tick mode", %{spec: spec} do
      result = Variant.set_tick_mode(spec, :turn_based, %{parallel: true})
      assert result.tick_config.mode == :turn_based
      assert result.tick_config.opts == %{parallel: true}
    end
  end

  describe "add_role/3" do
    test "adds new role with defaults", %{spec: spec} do
      result = Variant.add_role(spec, :supervisor)
      assert length(result.roles) == 3
      supervisor = Enum.find(result.roles, &(&1.name == :supervisor))
      assert supervisor.count == 1
      assert supervisor.backend == :bwrap
    end

    test "adds new role with options", %{spec: spec} do
      result = Variant.add_role(spec, :supervisor, count: 2, model: "gpt-4", config: %{auth: true})
      supervisor = Enum.find(result.roles, &(&1.name == :supervisor))
      assert supervisor.count == 2
      assert supervisor.model == "gpt-4"
      assert supervisor.config == %{auth: true}
    end
  end

  describe "remove_role/2" do
    test "removes role and its connections", %{spec: spec} do
      result = Variant.remove_role(spec, :worker)
      assert length(result.roles) == 1
      assert Enum.all?(result.roles, &(&1.name != :worker))
      # Connection involving worker should be removed
      assert Enum.empty?(result.connections)
    end
  end

  describe "generate/3" do
    test "generates N variants", %{spec: spec} do
      variants =
        Variant.generate(spec, 5, fn spec, i ->
          Variant.set_agent_count(spec, :worker, i + 1)
        end)

      assert length(variants) == 5

      Enum.with_index(variants, fn variant, i ->
        worker = Enum.find(variant.roles, &(&1.name == :worker))
        assert worker.count == i + 1
      end)
    end
  end

  describe "clone/2" do
    test "creates copy with new name", %{spec: spec} do
      result = Variant.clone(spec, "cloned_sim")
      assert result.name == "cloned_sim"
      # Original unchanged
      assert spec.name == "test_sim"
    end
  end

  describe "get_role/2" do
    test "returns role if exists", %{spec: spec} do
      role = Variant.get_role(spec, :worker)
      assert role.name == :worker
      assert role.count == 2
    end

    test "returns nil if not found", %{spec: spec} do
      assert Variant.get_role(spec, :nonexistent) == nil
    end
  end

  describe "role_names/1" do
    test "returns all role names", %{spec: spec} do
      names = Variant.role_names(spec)
      assert names == [:worker, :manager]
    end
  end

  describe "chained operations" do
    test "supports method chaining", %{spec: spec} do
      result =
        spec
        |> Variant.set_name("chained_sim")
        |> Variant.set_agent_count(:worker, 10)
        |> Variant.set_model(:worker, "claude-3")
        |> Variant.add_connection(:manager, :worker, bidirectional: true)
        |> Variant.set_steps(50)

      assert result.name == "chained_sim"
      worker = Enum.find(result.roles, &(&1.name == :worker))
      assert worker.count == 10
      assert worker.model == "claude-3"
      assert length(result.connections) == 2
      assert result.steps == 50
    end
  end
end
