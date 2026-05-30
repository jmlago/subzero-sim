defmodule SubzeroSim.Store.MetricsStore do
  @moduledoc """
  DETS-backed store for simulation metrics.

  Uses DETS for cross-process persistence, allowing CLI commands
  to access metrics from running simulations.

  Stores computed metrics per step, enabling:
  - Time-series analysis of metric values
  - Querying current or historical metrics
  - Export of metrics data
  """

  @table :subzero_sim_metrics
  @dets_dir Path.expand("~/.subzeroclaw/runtime")
  @dets_file Path.join(@dets_dir, "metrics.dets")

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
  Stores a metric value for a specific step.
  """
  @spec put(String.t(), atom(), non_neg_integer(), term()) :: :ok
  def put(sim_name, metric_name, step, value) do
    ensure_table()
    :dets.insert(@table, {{sim_name, metric_name, step}, value})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Gets a metric value for a specific step.
  """
  @spec get(String.t(), atom(), non_neg_integer()) :: term() | nil
  def get(sim_name, metric_name, step) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, metric_name, step}) do
      [{_, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Gets the latest value of a metric.
  """
  @spec get_latest(String.t(), atom()) :: {non_neg_integer(), term()} | nil
  def get_latest(sim_name, metric_name) do
    ensure_table()

    # Find all entries for this metric and get the one with highest step
    pattern = {{sim_name, metric_name, :_}, :_}

    case :dets.match_object(@table, pattern) do
      [] ->
        nil

      entries ->
        entries
        |> Enum.max_by(fn {{_, _, step}, _} -> step end)
        |> then(fn {{_, _, step}, value} -> {step, value} end)
    end
  end

  @doc """
  Gets all values of a metric as a time series.
  """
  @spec get_series(String.t(), atom()) :: [{non_neg_integer(), term()}]
  def get_series(sim_name, metric_name) do
    ensure_table()

    pattern = {{sim_name, metric_name, :_}, :_}

    :dets.match_object(@table, pattern)
    |> Enum.map(fn {{_, _, step}, value} -> {step, value} end)
    |> Enum.sort_by(fn {step, _} -> step end)
  end

  @doc """
  Gets all metrics for a specific step.
  """
  @spec get_step_metrics(String.t(), non_neg_integer()) :: map()
  def get_step_metrics(sim_name, step) do
    ensure_table()

    pattern = {{sim_name, :_, step}, :_}

    :dets.match_object(@table, pattern)
    |> Enum.reduce(%{}, fn {{_, metric_name, _}, value}, acc ->
      Map.put(acc, metric_name, value)
    end)
  end

  @doc """
  Gets all current metrics (latest value for each metric).
  """
  @spec get_current(String.t()) :: map()
  def get_current(sim_name) do
    ensure_table()

    # Find all unique metric names
    pattern = {{sim_name, :_, :_}, :_}

    :dets.match_object(@table, pattern)
    |> Enum.reduce(%{}, fn {{_, metric_name, step}, value}, acc ->
      case Map.get(acc, metric_name) do
        nil ->
          Map.put(acc, metric_name, {step, value})

        {existing_step, _} when step > existing_step ->
          Map.put(acc, metric_name, {step, value})

        _ ->
          acc
      end
    end)
    |> Enum.reduce(%{}, fn {metric_name, {_, value}}, acc ->
      Map.put(acc, metric_name, value)
    end)
  end

  @doc """
  Exports all metrics as a map of metric_name => series.
  """
  @spec export(String.t()) :: map()
  def export(sim_name) do
    ensure_table()

    pattern = {{sim_name, :_, :_}, :_}

    :dets.match_object(@table, pattern)
    |> Enum.group_by(fn {{_, metric_name, _}, _} -> metric_name end)
    |> Enum.map(fn {metric_name, entries} ->
      series =
        entries
        |> Enum.map(fn {{_, _, step}, value} -> %{step: step, value: value} end)
        |> Enum.sort_by(& &1.step)

      {metric_name, series}
    end)
    |> Map.new()
  end

  @doc """
  Lists all metric names for a simulation.
  """
  @spec list_metrics(String.t()) :: [atom()]
  def list_metrics(sim_name) do
    ensure_table()

    pattern = {{sim_name, :_, :_}, :_}

    :dets.match_object(@table, pattern)
    |> Enum.map(fn {{_, metric_name, _}, _} -> metric_name end)
    |> Enum.uniq()
  end

  @doc """
  Cleans up all metrics for a simulation.
  """
  @spec cleanup(String.t()) :: :ok
  def cleanup(sim_name) do
    ensure_table()

    # Match all entries for this simulation and delete them
    :dets.match_object(@table, {{sim_name, :_, :_}, :_})
    |> Enum.each(fn {key, _} -> :dets.delete(@table, key) end)

    :dets.sync(@table)
    :ok
  end
end
