defmodule SubzeroSim.Store.ResultStore do
  @moduledoc """
  DETS-backed store for gateway results from child simulations.

  Stores the final_result data collected by Gateway objects from child simulations,
  allowing parent processes to retrieve results after child completion.
  """

  @table :subzero_sim_results

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
            file: String.to_charlist(Path.join(dir, "results.dets")),
            type: :set,
            auto_save: 1000
          )

        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Stores a gateway result for a simulation.
  """
  @spec put(String.t(), term()) :: :ok
  def put(sim_name, result) do
    ensure_table()
    :dets.insert(@table, {{sim_name, :result}, result})
    :dets.insert(@table, {{sim_name, :completed_at}, DateTime.utc_now()})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Gets the gateway result for a simulation.
  """
  @spec get(String.t()) :: term() | nil
  def get(sim_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, :result}) do
      [{_, result}] -> result
      [] -> nil
    end
  end

  @doc """
  Gets the completion timestamp for a simulation.
  """
  @spec get_completed_at(String.t()) :: DateTime.t() | nil
  def get_completed_at(sim_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, :completed_at}) do
      [{_, time}] -> time
      [] -> nil
    end
  end

  @doc """
  Checks if a result exists for a simulation.
  """
  @spec has_result?(String.t()) :: boolean()
  def has_result?(sim_name) do
    ensure_table()
    :dets.lookup(@table, {sim_name, :result}) != []
  end

  @doc """
  Cleans up result data for a simulation.
  """
  @spec cleanup(String.t()) :: :ok
  def cleanup(sim_name) do
    ensure_table()
    :dets.delete(@table, {sim_name, :result})
    :dets.delete(@table, {sim_name, :completed_at})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Lists all simulations with stored results.
  """
  @spec list_results() :: [String.t()]
  def list_results do
    ensure_table()

    :dets.match(@table, {{:"$1", :result}, :_})
    |> Enum.map(fn [name] -> name end)
  end
end
