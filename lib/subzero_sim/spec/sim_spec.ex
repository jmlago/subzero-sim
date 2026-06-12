defmodule SubzeroSim.Spec.SimSpec do
  @moduledoc """
  Main specification struct for a simulation.

  Contains all configuration needed to generate a genswarms config
  with injected Tick and Metrics objects.
  """

  alias SubzeroSim.Spec.{TickConfig, RoleSpec, ObjectSpec, Connection, MeasureSpec, HaltCondition}

  @type start_trigger ::
          :immediate
          | :on_ready
          | {:delayed, pos_integer()}
          | :manual

  @type t :: %__MODULE__{
          name: String.t(),
          tick_config: TickConfig.t(),
          start_trigger: start_trigger(),
          steps: pos_integer() | nil,
          roles: [RoleSpec.t()],
          objects: [ObjectSpec.t()],
          connections: [Connection.t()],
          measures: [MeasureSpec.t()],
          halt_conditions: [HaltCondition.t()],
          source_dir: String.t() | nil
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    :source_dir,
    tick_config: %TickConfig{},
    start_trigger: :immediate,
    steps: nil,
    roles: [],
    objects: [],
    connections: [],
    measures: [],
    halt_conditions: []
  ]

  @doc """
  Creates a new SimSpec with the given name.
  """
  @spec new(String.t()) :: t()
  def new(name) when is_binary(name) do
    %__MODULE__{name: name}
  end

  @doc """
  Returns all agent names that will be generated from roles.

  Expands role counts, e.g., `{:trader, 3}` becomes `[:trader_1, :trader_2, :trader_3]`.
  """
  @spec agent_names(t()) :: [atom()]
  def agent_names(%__MODULE__{roles: roles}) do
    Enum.flat_map(roles, fn role ->
      if role.count == 1 do
        [role.name]
      else
        for i <- 1..role.count, do: :"#{role.name}_#{i}"
      end
    end)
  end

  @doc """
  Returns all object names (user-defined only, not Tick/Metrics).
  """
  @spec object_names(t()) :: [atom()]
  def object_names(%__MODULE__{objects: objects}) do
    Enum.map(objects, & &1.name)
  end
end
