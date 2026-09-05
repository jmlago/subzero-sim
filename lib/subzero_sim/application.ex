defmodule SubzeroSim.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SubzeroSim.Store.Owner
    ]

    opts = [strategy: :one_for_one, name: SubzeroSim.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
