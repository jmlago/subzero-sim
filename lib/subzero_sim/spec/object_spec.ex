defmodule SubzeroSim.Spec.ObjectSpec do
  @moduledoc """
  Specification for a user-defined object in a simulation.

  Objects are non-agentic components that participate in the swarm topology.
  They receive/send messages but execute Elixir code instead of LLM calls.

  Note: The Tick and Metrics objects are injected automatically by the compiler
  and should not be specified here.
  """

  @type t :: %__MODULE__{
          name: atom(),
          handler: module(),
          config: map()
        }

  @enforce_keys [:name, :handler]
  defstruct [
    :name,
    :handler,
    config: %{}
  ]

  @doc """
  Creates a new ObjectSpec with the given name and handler module.
  """
  @spec new(atom(), module(), keyword()) :: t()
  def new(name, handler, opts \\ []) when is_atom(name) and is_atom(handler) do
    config = Keyword.get(opts, :config, %{})
    %__MODULE__{name: name, handler: handler, config: config}
  end
end
