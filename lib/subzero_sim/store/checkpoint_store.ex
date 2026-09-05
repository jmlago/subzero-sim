defmodule SubzeroSim.Store.CheckpointStore do
  @moduledoc """
  DETS-backed store for simulation checkpoints (pause/resume state).

  Stores checkpoint data when a simulation is paused, allowing it to be
  resumed later from the same state.
  """

  @table :subzero_sim_checkpoints

  @doc """
  Ensures the DETS table exists.
  """
  @spec ensure_table() :: :ok
  def ensure_table do
    case :dets.info(@table) do
      :undefined ->
        dir =
          Application.get_env(:subzero_sim, :data_dir, "~/.subzeroclaw/runtime") |> Path.expand()

        File.mkdir_p!(dir)

        {:ok, @table} =
          :dets.open_file(@table,
            file: String.to_charlist(Path.join(dir, "checkpoints.dets")),
            type: :set,
            auto_save: 1000
          )

        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Saves a checkpoint for a simulation.

  The checkpoint contains all state needed to resume:
  - current_step
  - paused_at timestamp
  - tick_state (optional internal state)
  """
  @spec save(String.t(), map()) :: :ok
  def save(sim_name, checkpoint) do
    ensure_table()
    checkpoint = Map.put(checkpoint, :paused_at, DateTime.utc_now())
    :dets.insert(@table, {sim_name, checkpoint})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Gets the checkpoint for a simulation.
  """
  @spec get(String.t()) :: map() | nil
  def get(sim_name) do
    ensure_table()

    case :dets.lookup(@table, sim_name) do
      [{_, checkpoint}] -> checkpoint
      [] -> nil
    end
  end

  @doc """
  Checks if a checkpoint exists for a simulation.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(sim_name) do
    ensure_table()
    :dets.lookup(@table, sim_name) != []
  end

  @doc """
  Deletes the checkpoint for a simulation.
  """
  @spec delete(String.t()) :: :ok
  def delete(sim_name) do
    ensure_table()
    :dets.delete(@table, sim_name)
    :dets.sync(@table)
    :ok
  end

  @doc """
  Lists all simulations with checkpoints.
  """
  @spec list() :: [String.t()]
  def list do
    ensure_table()

    :dets.match(@table, {:"$1", :_})
    |> Enum.map(fn [name] -> name end)
  end
end
