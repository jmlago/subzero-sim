defmodule SubzeroSim.Store.StateStore do
  @moduledoc """
  DETS-backed store for agent states.

  Uses DETS for cross-process persistence, allowing CLI commands
  to access agent states from running simulations.

  Stores the reported state of each agent, enabling:
  - State collection for metric computation
  - State history tracking
  - Agent state querying
  """

  @table :subzero_sim_states
  @dets_dir Path.expand("~/.subzeroclaw/runtime")
  @dets_file Path.join(@dets_dir, "states.dets")

  @doc """
  Ensures the DETS table exists.
  """
  @spec ensure_table() :: :ok
  def ensure_table do
    case :dets.info(@table) do
      :undefined ->
        File.mkdir_p!(@dets_dir)
        {:ok, @table} = :dets.open_file(@table, [
          file: String.to_charlist(@dets_file),
          type: :set,
          auto_save: 1000
        ])
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Stores an agent's state for a specific step.
  """
  @spec put(String.t(), atom(), non_neg_integer(), map()) :: :ok
  def put(sim_name, agent_name, step, state) do
    ensure_table()
    :dets.insert(@table, {{sim_name, agent_name, step}, state})
    # Also update the "current" state
    :dets.insert(@table, {{sim_name, agent_name, :current}, state})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Gets an agent's state for a specific step.
  """
  @spec get(String.t(), atom(), non_neg_integer()) :: map() | nil
  def get(sim_name, agent_name, step) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, agent_name, step}) do
      [{_, state}] -> state
      [] -> nil
    end
  end

  @doc """
  Gets an agent's current (latest) state.
  """
  @spec get_current(String.t(), atom()) :: map() | nil
  def get_current(sim_name, agent_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, agent_name, :current}) do
      [{_, state}] -> state
      [] -> nil
    end
  end

  @doc """
  Gets all agents' states for a specific step.
  """
  @spec get_all_states(String.t(), non_neg_integer()) :: map()
  def get_all_states(sim_name, step) do
    ensure_table()

    pattern = {{sim_name, :_, step}, :_}

    :dets.match_object(@table, pattern)
    |> Enum.reduce(%{}, fn {{_, agent_name, _}, state}, acc ->
      Map.put(acc, agent_name, state)
    end)
  end

  @doc """
  Gets all agents' current states.
  """
  @spec get_all_current(String.t()) :: map()
  def get_all_current(sim_name) do
    ensure_table()

    pattern = {{sim_name, :_, :current}, :_}

    :dets.match_object(@table, pattern)
    |> Enum.reduce(%{}, fn {{_, agent_name, _}, state}, acc ->
      Map.put(acc, agent_name, state)
    end)
  end

  @doc """
  Gets the state history for an agent.
  """
  @spec get_history(String.t(), atom()) :: [{non_neg_integer(), map()}]
  def get_history(sim_name, agent_name) do
    ensure_table()

    pattern = {{sim_name, agent_name, :_}, :_}

    :dets.match_object(@table, pattern)
    |> Enum.filter(fn {{_, _, step}, _} -> is_integer(step) end)
    |> Enum.map(fn {{_, _, step}, state} -> {step, state} end)
    |> Enum.sort_by(fn {step, _} -> step end)
  end

  @doc """
  Cleans up all state data for a simulation.
  """
  @spec cleanup(String.t()) :: :ok
  def cleanup(sim_name) do
    ensure_table()

    # Get all keys matching this simulation
    pattern = {{sim_name, :_, :_}, :_}

    :dets.match_object(@table, pattern)
    |> Enum.each(fn {key, _} -> :dets.delete(@table, key) end)

    :dets.sync(@table)
    :ok
  end
end
