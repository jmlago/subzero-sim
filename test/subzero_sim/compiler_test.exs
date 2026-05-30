defmodule SubzeroSim.CompilerTest do
  use ExUnit.Case, async: true

  alias SubzeroSim.Compiler
  alias SubzeroSim.Spec.{SimSpec, TickConfig, RoleSpec, ObjectSpec, Connection, MeasureSpec}

  describe "compile/1" do
    test "compiles a minimal spec" do
      spec = %SimSpec{
        name: "test_sim",
        roles: [%RoleSpec{name: :worker}]
      }

      assert {:ok, config} = Compiler.compile(spec)
      assert config[:name] == "test_sim"
      assert length(config[:agents]) == 1
      assert [%{name: :worker, backend: :bwrap}] = config[:agents]
    end

    test "expands roles with count > 1" do
      spec = %SimSpec{
        name: "test",
        roles: [%RoleSpec{name: :trader, count: 3}]
      }

      assert {:ok, config} = Compiler.compile(spec)
      assert length(config[:agents]) == 3

      names = Enum.map(config[:agents], & &1[:name])
      assert names == [:trader_1, :trader_2, :trader_3]
    end

    test "preserves role configuration in expanded agents" do
      spec = %SimSpec{
        name: "test",
        roles: [
          %RoleSpec{
            name: :worker,
            count: 2,
            backend: {:docker, "worker-image"},
            skill: "worker.md",
            model: "gpt-4",
            config: %{energy: 100}
          }
        ]
      }

      assert {:ok, config} = Compiler.compile(spec)

      for agent <- config[:agents] do
        assert agent[:backend] == {:docker, "worker-image"}
        assert agent[:skills] == ["worker.md"]
        assert agent[:model] == "gpt-4"
        assert agent[:config] == %{energy: 100}
      end
    end

    test "includes user-defined objects" do
      spec = %SimSpec{
        name: "test",
        roles: [%RoleSpec{name: :player}],
        objects: [%ObjectSpec{name: :game, handler: MyApp.Game, config: %{max_rounds: 10}}]
      }

      assert {:ok, config} = Compiler.compile(spec)

      user_objects = Enum.filter(config[:objects], &(&1[:name] not in [:tick, :metrics]))
      assert [%{name: :game, handler: MyApp.Game, config: %{max_rounds: 10}}] = user_objects
    end

    test "injects tick object with config" do
      spec = %SimSpec{
        name: "test_sim",
        tick_config: %TickConfig{mode: :turn_based, opts: %{parallel: true}},
        start_trigger: :on_ready,
        steps: 100,
        roles: [%RoleSpec{name: :worker}]
      }

      assert {:ok, config} = Compiler.compile(spec)

      tick = Enum.find(config[:objects], &(&1[:name] == :tick))
      assert tick[:handler] == SubzeroSim.Objects.Tick
      assert tick[:config][:sim_name] == "test_sim"
      assert tick[:config][:mode] == :turn_based
      assert tick[:config][:opts] == %{parallel: true}
      assert tick[:config][:start_trigger] == :on_ready
      assert tick[:config][:agent_names] == [:worker]
      assert tick[:config][:max_steps] == 100
    end

    test "injects metrics object with config" do
      measure_fn = fn states -> Enum.count(states) end

      spec = %SimSpec{
        name: "test_sim",
        roles: [%RoleSpec{name: :worker, count: 2}],
        measures: [%MeasureSpec{name: :count, function: measure_fn}],
        halt_conditions: []
      }

      assert {:ok, config} = Compiler.compile(spec)

      metrics = Enum.find(config[:objects], &(&1[:name] == :metrics))
      assert metrics[:handler] == SubzeroSim.Objects.Metrics
      assert metrics[:config][:sim_name] == "test_sim"
      assert metrics[:config][:agent_names] == [:worker_1, :worker_2]
      assert length(metrics[:config][:measures]) == 1
    end
  end

  describe "topology generation" do
    test "expands role-to-role connections" do
      spec = %SimSpec{
        name: "test",
        roles: [
          %RoleSpec{name: :buyer, count: 2},
          %RoleSpec{name: :seller, count: 2}
        ],
        connections: [%Connection{from: :buyer, to: :seller}]
      }

      assert {:ok, config} = Compiler.compile(spec)

      # Filter to just buyer->seller edges (tuples now)
      edges =
        Enum.filter(config[:topology], fn {from, to} ->
          Atom.to_string(from) |> String.starts_with?("buyer") and
            Atom.to_string(to) |> String.starts_with?("seller")
        end)

      # Should have 2 buyers × 2 sellers = 4 edges
      assert length(edges) == 4
      assert {:buyer_1, :seller_1} in edges
      assert {:buyer_1, :seller_2} in edges
      assert {:buyer_2, :seller_1} in edges
      assert {:buyer_2, :seller_2} in edges
    end

    test "handles bidirectional connections" do
      spec = %SimSpec{
        name: "test",
        roles: [
          %RoleSpec{name: :a},
          %RoleSpec{name: :b}
        ],
        connections: [%Connection{from: :a, to: :b, bidirectional: true}]
      }

      assert {:ok, config} = Compiler.compile(spec)

      # Filter to just a<->b edges
      edges =
        Enum.filter(config[:topology], fn {from, to} ->
          (from == :a and to == :b) or (from == :b and to == :a)
        end)

      assert {:a, :b} in edges
      assert {:b, :a} in edges
    end

    test "adds tick to all agents edges" do
      spec = %SimSpec{
        name: "test",
        roles: [%RoleSpec{name: :worker, count: 3}]
      }

      assert {:ok, config} = Compiler.compile(spec)

      tick_edges =
        Enum.filter(config[:topology], fn {from, _to} -> from == :tick end)

      # tick -> worker_1, worker_2, worker_3, metrics
      agent_edges =
        Enum.filter(tick_edges, fn {_from, to} ->
          Atom.to_string(to) |> String.starts_with?("worker")
        end)

      assert length(agent_edges) == 3
    end

    test "adds all agents to metrics edges" do
      spec = %SimSpec{
        name: "test",
        roles: [%RoleSpec{name: :worker, count: 2}]
      }

      assert {:ok, config} = Compiler.compile(spec)

      metrics_edges =
        Enum.filter(config[:topology], fn {_from, to} -> to == :metrics end)

      # worker_1 -> metrics, worker_2 -> metrics, tick -> metrics
      assert length(metrics_edges) == 3
    end

    test "adds tick-metrics coordination edges" do
      spec = %SimSpec{
        name: "test",
        roles: [%RoleSpec{name: :worker}]
      }

      assert {:ok, config} = Compiler.compile(spec)

      assert {:tick, :metrics} in config[:topology]
      assert {:metrics, :tick} in config[:topology]
    end

    test "handles connections to objects" do
      spec = %SimSpec{
        name: "test",
        roles: [%RoleSpec{name: :player, count: 2}],
        objects: [%ObjectSpec{name: :game, handler: MyApp.Game}],
        connections: [%Connection{from: :player, to: :game, bidirectional: true}]
      }

      assert {:ok, config} = Compiler.compile(spec)

      player_to_game =
        Enum.filter(config[:topology], fn {from, to} ->
          Atom.to_string(from) |> String.starts_with?("player") and to == :game
        end)

      game_to_player =
        Enum.filter(config[:topology], fn {from, to} ->
          from == :game and Atom.to_string(to) |> String.starts_with?("player")
        end)

      assert length(player_to_game) == 2
      assert length(game_to_player) == 2
    end
  end

  describe "DSL integration" do
    test "compiles a full DSL spec" do
      spec =
        Code.eval_string("""
        use SubzeroSim.DSL

        simulation "market_sim" do
          tick :turn_based, parallel: true
          start :immediate
          steps 50

          agent :buyer, count: 3, backend: :bwrap do
            skill "buyer.md"
            config budget: 1000
          end

          agent :seller, count: 2 do
            skill "seller.md"
            config inventory: 100
          end

          connect :buyer, :seller, bidirectional: true

          measure :total_budget, fn states ->
            states
            |> Map.values()
            |> Enum.map(fn s -> Map.get(s, "budget", 0) end)
            |> Enum.sum()
          end

          halt after: 50
        end
        """)
        |> elem(0)

      assert {:ok, config} = Compiler.compile(spec)

      # Verify agents
      assert length(config[:agents]) == 5
      buyer_names =
        config[:agents]
        |> Enum.filter(&(Atom.to_string(&1[:name]) |> String.starts_with?("buyer")))
        |> Enum.map(& &1[:name])

      assert buyer_names == [:buyer_1, :buyer_2, :buyer_3]

      # Verify tick config
      tick = Enum.find(config[:objects], &(&1[:name] == :tick))
      assert tick[:config][:mode] == :turn_based
      assert tick[:config][:opts][:parallel] == true
      assert tick[:config][:max_steps] == 50

      # Verify topology has buyer-seller connections
      buyer_seller_edges =
        Enum.filter(config[:topology], fn {from, to} ->
          Atom.to_string(from) |> String.starts_with?("buyer") and
            Atom.to_string(to) |> String.starts_with?("seller")
        end)

      # 3 buyers × 2 sellers = 6 edges
      assert length(buyer_seller_edges) == 6
    end
  end
end
