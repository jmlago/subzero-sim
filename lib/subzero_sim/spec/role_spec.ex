defmodule SubzeroSim.Spec.RoleSpec do
  @moduledoc """
  Specification for an agent role in a simulation.

  A role defines a type of agent. Multiple agents can be created from a single role
  using the `count` field. For example, a role named `:trader` with `count: 5` will
  generate agents `:trader_1`, `:trader_2`, ..., `:trader_5`.
  """

  @type backend ::
          :bwrap
          | {:bwrap, map()}
          | :local
          | {:docker, String.t()}
          | {:docker, String.t(), map()}
          | {:ssh, String.t()}
          | {:ssh, String.t(), map()}

  @type t :: %__MODULE__{
          name: atom(),
          count: pos_integer(),
          preset: atom() | nil,
          skill: String.t() | nil,
          backend: backend(),
          model: String.t() | nil,
          endpoint: String.t() | nil,
          config: map()
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    :preset,
    :skill,
    :model,
    :endpoint,
    count: 1,
    backend: :bwrap,
    config: %{}
  ]

  @doc """
  Creates a new RoleSpec with the given name.
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    struct!(__MODULE__, [{:name, name} | opts])
  end

  @doc """
  Expands a role into individual agent names.

  If count is 1, returns `[name]`.
  If count > 1, returns `[name_1, name_2, ..., name_N]`.
  """
  @spec expand_names(t()) :: [atom()]
  def expand_names(%__MODULE__{name: name, count: 1}), do: [name]

  def expand_names(%__MODULE__{name: name, count: count}) when count > 1 do
    for i <- 1..count, do: :"#{name}_#{i}"
  end
end
