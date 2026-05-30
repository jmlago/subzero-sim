defmodule SubzeroSim.DSLTest do
  use ExUnit.Case, async: true

  alias SubzeroSim.{Loader, Validator}
  alias SubzeroSim.Spec.{SimSpec, TickConfig, RoleSpec, Connection, MeasureSpec, HaltCondition}

  describe "simulation macro" do
    test "creates a SimSpec with name" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test_sim" do
          agent :worker
        end
        """)
        |> elem(0)

      assert %SimSpec{name: "test_sim"} = spec
    end

    test "sets tick mode" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          tick :turn_based, parallel: true
          agent :worker
        end
        """)
        |> elem(0)

      assert %TickConfig{mode: :turn_based, opts: %{parallel: true}} = spec.tick_config
    end

    test "sets time_interval tick mode" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          tick :time_interval, every: 60
          agent :worker
        end
        """)
        |> elem(0)

      assert %TickConfig{mode: :time_interval, opts: %{every: 60}} = spec.tick_config
    end

    test "sets output_count tick mode" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          tick :output_count, every: 10
          agent :worker
        end
        """)
        |> elem(0)

      assert %TickConfig{mode: :output_count, opts: %{every: 10}} = spec.tick_config
    end

    test "sets start trigger" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          start :on_ready
          agent :worker
        end
        """)
        |> elem(0)

      assert spec.start_trigger == :on_ready
    end

    test "sets delayed start trigger" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          start {:delayed, 5}
          agent :worker
        end
        """)
        |> elem(0)

      assert spec.start_trigger == {:delayed, 5}
    end

    test "sets steps" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          steps 100
          agent :worker
        end
        """)
        |> elem(0)

      assert spec.steps == 100
    end
  end

  describe "agent macro" do
    test "creates a role with defaults" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker
        end
        """)
        |> elem(0)

      assert [%RoleSpec{name: :worker, count: 1, backend: :bwrap}] = spec.roles
    end

    test "creates a role with count" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :trader, count: 5
        end
        """)
        |> elem(0)

      assert [%RoleSpec{name: :trader, count: 5}] = spec.roles
    end

    test "creates a role with block" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker, count: 3, backend: :openai do
            skill "worker.md"
            config energy: 100, health: 50
          end
        end
        """)
        |> elem(0)

      assert [role] = spec.roles
      assert role.name == :worker
      assert role.count == 3
      assert role.backend == :openai
      assert role.skill == "worker.md"
      assert role.config == %{energy: 100, health: 50}
    end

    test "creates multiple roles" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :buyer, count: 5
          agent :seller, count: 3
          agent :market
        end
        """)
        |> elem(0)

      assert length(spec.roles) == 3
      assert Enum.map(spec.roles, & &1.name) == [:buyer, :seller, :market]
    end
  end

  describe "object macro" do
    test "creates an object" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :player
          object :game, handler: MyApp.Game
        end
        """)
        |> elem(0)

      assert [obj] = spec.objects
      assert obj.name == :game
      assert obj.handler == MyApp.Game
    end

    test "creates an object with config" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :player
          object :game, handler: MyApp.Game, config: %{max_rounds: 10}
        end
        """)
        |> elem(0)

      assert [obj] = spec.objects
      assert obj.config == %{max_rounds: 10}
    end
  end

  describe "connect macro" do
    test "creates a unidirectional connection" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :a
          agent :b
          connect :a, :b
        end
        """)
        |> elem(0)

      assert [%Connection{from: :a, to: :b, bidirectional: false}] = spec.connections
    end

    test "creates a bidirectional connection" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :a
          agent :b
          connect :a, :b, bidirectional: true
        end
        """)
        |> elem(0)

      assert [%Connection{from: :a, to: :b, bidirectional: true}] = spec.connections
    end
  end

  describe "measure macro" do
    test "creates a measure" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker
          measure :total, fn states -> Enum.count(states) end
        end
        """)
        |> elem(0)

      assert [%MeasureSpec{name: :total, every: 1}] = spec.measures
      assert is_function(hd(spec.measures).function, 1)
    end

    test "creates a measure with every option" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker
          measure :expensive, [every: 10], fn states -> Enum.count(states) end
        end
        """)
        |> elem(0)

      assert [%MeasureSpec{name: :expensive, every: 10}] = spec.measures
    end
  end

  describe "halt macro" do
    test "creates after_steps halt condition" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker
          halt after: 50
        end
        """)
        |> elem(0)

      assert [%HaltCondition{type: :after_steps, value: 50}] = spec.halt_conditions
    end

    test "creates when_predicate halt condition" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker
          halt when: fn metrics -> metrics[:done] == true end
        end
        """)
        |> elem(0)

      assert [%HaltCondition{type: :when_predicate}] = spec.halt_conditions
      assert is_function(hd(spec.halt_conditions).value, 1)
    end

    test "creates multiple halt conditions" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker
          halt after: 100
          halt when: fn metrics -> metrics[:converged] end
        end
        """)
        |> elem(0)

      assert length(spec.halt_conditions) == 2
    end

    test "creates when_history halt condition" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker
          halt when_history: fn {_metrics, _history} -> true end
        end
        """)
        |> elem(0)

      assert [%HaltCondition{type: :when_history}] = spec.halt_conditions
      assert is_function(hd(spec.halt_conditions).value, 1)
    end

    test "creates metric_converged halt condition" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker
          halt converged: [metric: :wealth, threshold: 100, window: 10]
        end
        """)
        |> elem(0)

      assert [%HaltCondition{type: :metric_converged, value: value}] = spec.halt_conditions
      assert value.metric == :wealth
      assert value.threshold == 100
      assert value.window == 10
    end

    test "creates metric_plateaued halt condition" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :worker
          halt plateaued: [metric: :gini, threshold: 0.01]
        end
        """)
        |> elem(0)

      assert [%HaltCondition{type: :metric_plateaued, value: value}] = spec.halt_conditions
      assert value.metric == :gini
      assert value.threshold == 0.01
      assert value.window == 10  # default window
    end
  end

  describe "Loader" do
    test "loads a .sim file" do
      path = Path.join([__DIR__, "..", "support", "fixtures", "simple.sim"])
      assert {:ok, %SimSpec{name: "simple_test"}} = Loader.load(path)
    end

    test "returns error for missing file" do
      assert {:error, {:file_not_found, _}} = Loader.load("nonexistent.sim")
    end

    test "loads from string" do
      code = """
      use SubzeroSim.DSL
      simulation "from_string" do
        agent :test
      end
      """

      assert {:ok, %SimSpec{name: "from_string"}} = Loader.load_string(code)
    end
  end

  describe "Validator" do
    test "validates a valid spec" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "valid" do
          agent :worker, count: 2
          connect :worker, :worker
          steps 10
        end
        """)
        |> elem(0)

      assert :ok = Validator.validate(spec)
    end

    test "rejects empty name" do
      spec = %SimSpec{name: "", roles: [%RoleSpec{name: :worker}]}
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "empty"))
    end

    test "rejects no roles" do
      spec = %SimSpec{name: "test", roles: []}
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "role"))
    end

    test "rejects invalid role count" do
      spec = %SimSpec{name: "test", roles: [%RoleSpec{name: :worker, count: 0}]}
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "count"))
    end

    test "rejects invalid tick mode" do
      spec = %SimSpec{
        name: "test",
        roles: [%RoleSpec{name: :worker}],
        tick_config: %TickConfig{mode: :invalid}
      }

      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "tick mode"))
    end

    test "rejects time_interval without every" do
      spec = %SimSpec{
        name: "test",
        roles: [%RoleSpec{name: :worker}],
        tick_config: %TickConfig{mode: :time_interval}
      }

      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, ":every"))
    end

    test "rejects invalid connection references" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL
        simulation "test" do
          agent :a
          connect :a, :nonexistent
        end
        """)
        |> elem(0)

      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "nonexistent"))
    end

    test "rejects invalid start trigger" do
      spec = %SimSpec{
        name: "test",
        roles: [%RoleSpec{name: :worker}],
        start_trigger: :invalid
      }

      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "start trigger"))
    end
  end
end
