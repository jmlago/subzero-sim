defmodule SubzeroSim.Candidate do
  @moduledoc """
  Decodes untrusted JSON patches against an operator-owned simulation.

  Candidates may change counts and inline skills of explicitly mutable roles,
  and connections between those roles. They cannot supply code, objects,
  metrics, models, endpoints, backends, filesystem paths, or execution budgets.
  This is a data decoder, not a sandbox for Elixir. Loader.load/1 remains a
  trusted-code API and must never receive generated candidate files.
  """

  alias SubzeroSim.Spec.{SimSpec, Connection}

  @max_bytes 262_144

  @doc """
  Returns a patched spec and inline skills, without writing or evaluating code.

  The mutable_roles option is required; omitted roles are immutable. max_agents
  is an operator limit, default 16. Skills are keyed by existing role atoms.
  The caller must deploy these skills only into isolated agent workspaces.
  """
  def decode(json, base, opts \\ [])

  def decode(json, %SimSpec{} = base, opts) when is_binary(json) do
    with true <- byte_size(json) <= @max_bytes,
         {:ok, %{"version" => 1} = patch} <- Jason.decode(json),
         true <- keys?(patch, ["version", "roles", "connections"]),
         mutable when is_list(mutable) <- Keyword.get(opts, :mutable_roles),
         true <- Enum.all?(mutable, &Enum.any?(base.roles, fn role -> role.name == &1 end)),
         limit when is_integer(limit) and limit > 0 <- Keyword.get(opts, :max_agents, 16),
         {:ok, roles, skills} <-
           patch_roles(Map.get(patch, "roles", %{}), base.roles, mutable, limit),
         true <- Enum.sum(Enum.map(roles, & &1.count)) <= limit,
         {:ok, connections} <- patch_connections(patch["connections"], base, mutable),
         spec = %{base | roles: roles, connections: connections},
         :ok <- SubzeroSim.Validator.validate(spec) do
      {:ok, spec, skills}
    else
      _ -> {:error, :invalid_candidate}
    end
  end

  def decode(_, _, _), do: {:error, :invalid_candidate}

  defp patch_roles(patches, roles, mutable, limit) when is_map(patches) do
    allowed = Map.new(Enum.filter(roles, &(&1.name in mutable)), &{to_string(&1.name), &1.name})

    if Enum.all?(patches, fn {key, patch} ->
         Map.has_key?(allowed, key) and is_map(patch) and keys?(patch, ["count", "skill"]) and
           (not Map.has_key?(patch, "count") or
              (is_integer(patch["count"]) and patch["count"] in 1..limit)) and
           (not Map.has_key?(patch, "skill") or
              (is_binary(patch["skill"]) and byte_size(patch["skill"]) in 1..65_536))
       end) do
      patched =
        Enum.map(roles, fn role ->
          patch = Map.get(patches, to_string(role.name), %{})
          %{role | count: Map.get(patch, "count", role.count)}
        end)

      skills = for {name, %{"skill" => skill}} <- patches, into: %{}, do: {allowed[name], skill}
      {:ok, patched, skills}
    else
      {:error, :invalid_roles}
    end
  end

  defp patch_roles(_, _, _, _), do: {:error, :invalid_roles}

  defp patch_connections(nil, base, _mutable), do: {:ok, base.connections}

  defp patch_connections(edges, base, mutable) when is_list(edges) and length(edges) <= 256 do
    names = Map.new(mutable, &{to_string(&1), &1})

    if Enum.all?(edges, fn
         [from, to] -> Map.has_key?(names, from) and Map.has_key?(names, to) and from != to
         _ -> false
       end) do
      # Evaluation/object edges and edges to immutable roles cannot be removed.
      fixed = Enum.reject(base.connections, &(&1.from in mutable and &1.to in mutable))

      changed =
        Enum.map(edges, fn [from, to] -> %Connection{from: names[from], to: names[to]} end)

      {:ok, Enum.uniq(fixed ++ changed)}
    else
      {:error, :invalid_connections}
    end
  end

  defp patch_connections(_, _, _), do: {:error, :invalid_connections}

  defp keys?(map, allowed), do: Enum.all?(Map.keys(map), &(&1 in allowed))
end
