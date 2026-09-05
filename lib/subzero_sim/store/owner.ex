defmodule SubzeroSim.Store.Owner do
  @moduledoc """
  Keeps the runtime DETS tables open for the application's lifetime.

  A short-lived evaluator or Gateway must not be their only owner: its exit
  would close the table between another process's ensure_table and write.
  """
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    for store <- [
          SubzeroSim.Store.RuntimeStore,
          SubzeroSim.Store.StateStore,
          SubzeroSim.Store.MetricsStore,
          SubzeroSim.Store.ResultStore,
          SubzeroSim.Store.CheckpointStore
        ] do
      :ok = store.ensure_table()
    end

    {:ok, nil}
  end
end
