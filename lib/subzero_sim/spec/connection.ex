defmodule SubzeroSim.Spec.Connection do
  @moduledoc """
  Specification for a connection between nodes in the simulation topology.

  Connections define the communication paths between agents, objects, and roles.
  The compiler expands role connections to per-agent edges.

  ## Connection Types

  - Role to role: `{:trader, :market}` - All traders connect to all markets
  - Agent to object: `{:player_1, :game}` - Specific agent to object
  - Object to role: `{:tick, :trader}` - Object broadcasts to all traders

  ## Direction

  Connections are directional by default (from → to), meaning `from` can send
  messages to `to`. Use `bidirectional: true` to create edges in both directions.
  """

  @type node_ref :: atom()

  @type t :: %__MODULE__{
          from: node_ref(),
          to: node_ref(),
          bidirectional: boolean()
        }

  @enforce_keys [:from, :to]
  defstruct [
    :from,
    :to,
    bidirectional: false
  ]

  @doc """
  Creates a new Connection from one node to another.
  """
  @spec new(node_ref(), node_ref(), keyword()) :: t()
  def new(from, to, opts \\ []) when is_atom(from) and is_atom(to) do
    bidirectional = Keyword.get(opts, :bidirectional, false)
    %__MODULE__{from: from, to: to, bidirectional: bidirectional}
  end

  @doc """
  Converts a connection to topology edges.

  Returns a list of `{from, to}` tuples. For bidirectional connections,
  returns both directions.
  """
  @spec to_edges(t()) :: [{atom(), atom()}]
  def to_edges(%__MODULE__{from: from, to: to, bidirectional: false}) do
    [{from, to}]
  end

  def to_edges(%__MODULE__{from: from, to: to, bidirectional: true}) do
    [{from, to}, {to, from}]
  end
end
