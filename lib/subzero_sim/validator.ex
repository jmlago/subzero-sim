defmodule SubzeroSim.Validator do
  @moduledoc """
  Validates SimSpec structs for coherence and completeness.
  """

  alias SubzeroSim.Spec.{SimSpec, TickConfig, RoleSpec, MeasureSpec}

  @doc """
  Validates a SimSpec.

  Returns `:ok` if valid, `{:error, reasons}` with a list of error messages if invalid.
  """
  @spec validate(SimSpec.t()) :: :ok | {:error, [String.t()]}
  def validate(%SimSpec{} = spec) do
    errors =
      []
      |> validate_name(spec)
      |> validate_roles(spec)
      |> validate_tick_config(spec)
      |> validate_start_trigger(spec)
      |> validate_connections(spec)
      |> validate_measures(spec)
      |> validate_steps(spec)
      |> Enum.reverse()

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_name(errors, %SimSpec{name: name}) do
    cond do
      not is_binary(name) ->
        ["Simulation name must be a string" | errors]

      String.trim(name) == "" ->
        ["Simulation name cannot be empty" | errors]

      true ->
        errors
    end
  end

  defp validate_roles(errors, %SimSpec{roles: roles}) do
    if Enum.empty?(roles) do
      ["At least one agent role must be defined" | errors]
    else
      Enum.reduce(roles, errors, &validate_role/2)
    end
  end

  defp validate_role(%RoleSpec{} = role, errors) do
    errors
    |> validate_role_name(role)
    |> validate_role_count(role)
    |> validate_role_backend(role)
  end

  defp validate_role_name(errors, %RoleSpec{name: name}) do
    if is_atom(name) and name not in [nil, :tick, :metrics] do
      errors
    else
      ["Role name must be an atom (not nil, :tick, or :metrics), got: #{inspect(name)}" | errors]
    end
  end

  defp validate_role_count(errors, %RoleSpec{name: name, count: count}) do
    if is_integer(count) and count >= 1 do
      errors
    else
      ["Role #{inspect(name)} count must be >= 1, got: #{inspect(count)}" | errors]
    end
  end

  defp validate_role_backend(errors, %RoleSpec{name: name, backend: backend}) do
    if Genswarms.Config.SwarmConfig.valid_backend?(backend) do
      errors
    else
      [
        "Role #{inspect(name)} has invalid Genswarms backend: #{inspect(backend)}"
        | errors
      ]
    end
  end

  defp validate_tick_config(errors, %SimSpec{tick_config: tick_config}) do
    case TickConfig.validate(tick_config) do
      :ok -> errors
      {:error, msg} -> [msg | errors]
    end
  end

  defp validate_start_trigger(errors, %SimSpec{start_trigger: trigger}) do
    valid =
      case trigger do
        :immediate -> true
        :on_ready -> true
        :manual -> true
        {:delayed, n} when is_integer(n) and n > 0 -> true
        _ -> false
      end

    if valid do
      errors
    else
      [
        "Invalid start trigger: #{inspect(trigger)}, must be :immediate, :on_ready, :manual, or {:delayed, N}"
        | errors
      ]
    end
  end

  defp validate_connections(errors, %SimSpec{} = spec) do
    role_names = MapSet.new(Enum.map(spec.roles, & &1.name))
    object_names = MapSet.new(Enum.map(spec.objects, & &1.name))
    # System objects are auto-injected by the compiler — allow connecting to them
    system_names = MapSet.new([:tick, :metrics, :gateway])
    valid_names = role_names |> MapSet.union(object_names) |> MapSet.union(system_names)

    Enum.reduce(spec.connections, errors, fn conn, acc ->
      from_valid = MapSet.member?(valid_names, conn.from)
      to_valid = MapSet.member?(valid_names, conn.to)

      cond do
        not from_valid and not to_valid ->
          [
            "Connection references undefined nodes: #{inspect(conn.from)} and #{inspect(conn.to)}"
            | acc
          ]

        not from_valid ->
          ["Connection references undefined node: #{inspect(conn.from)}" | acc]

        not to_valid ->
          ["Connection references undefined node: #{inspect(conn.to)}" | acc]

        true ->
          acc
      end
    end)
  end

  defp validate_measures(errors, %SimSpec{measures: measures}) do
    Enum.reduce(measures, errors, fn measure, acc ->
      validate_measure(measure, acc)
    end)
  end

  defp validate_measure(%MeasureSpec{name: name, function: fun, every: every}, errors) do
    errors
    |> then(fn e ->
      if is_atom(name) and name != nil do
        e
      else
        ["Measure name must be a non-nil atom, got: #{inspect(name)}" | e]
      end
    end)
    |> then(fn e ->
      if is_function(fun, 1) do
        e
      else
        ["Measure #{inspect(name)} function must be arity-1" | e]
      end
    end)
    |> then(fn e ->
      if is_integer(every) and every >= 1 do
        e
      else
        ["Measure #{inspect(name)} :every must be >= 1, got: #{inspect(every)}" | e]
      end
    end)
  end

  defp validate_steps(errors, %SimSpec{steps: nil}), do: errors

  defp validate_steps(errors, %SimSpec{steps: steps}) do
    if is_integer(steps) and steps >= 1 do
      errors
    else
      ["steps must be a positive integer, got: #{inspect(steps)}" | errors]
    end
  end
end
