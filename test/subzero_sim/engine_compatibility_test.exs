defmodule SubzeroSim.EngineCompatibilityTest do
  use ExUnit.Case, async: true

  alias Genswarms.Config.SwarmConfig
  alias SubzeroSim.{Compiler, Validator}
  alias SubzeroSim.Spec.{SimSpec, RoleSpec}

  test "supported engine backends compile and parse without launching agents" do
    for backend <- [
          :local,
          :bwrap,
          {:bwrap, %{}},
          :mock,
          {:mock, %{}},
          :apple_container,
          {:apple_container, "image"},
          {:apple_container, "image", %{}},
          {:docker, "image"},
          {:docker, "image", %{}},
          {:ssh, "host"},
          {:ssh, "host", %{}},
          {:tmux, :claude},
          {:tmux, :codex},
          {:tmux, :opencode}
        ] do
      spec = %SimSpec{
        name: "compatibility",
        steps: 1,
        roles: [%RoleSpec{name: :worker, backend: backend}]
      }

      assert :ok = Validator.validate(spec)
      assert {:ok, config} = Compiler.compile(spec)
      assert {:ok, parsed} = SwarmConfig.parse(config)
      assert [agent] = parsed.agents
      assert agent.backend == backend
      assert is_atom(SwarmConfig.backend_module(backend))
      assert is_map(SwarmConfig.backend_config(backend))
    end
  end

  test "unsupported backend shapes fail validation" do
    for backend <- [:openai, {:docker, 123}, {:mock, "not-options"}, {:tmux, :unknown}] do
      spec = %SimSpec{name: "invalid", roles: [%RoleSpec{name: :worker, backend: backend}]}
      assert {:error, _} = Validator.validate(spec)
    end
  end
end
