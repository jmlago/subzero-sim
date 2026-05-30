defmodule SubzeroSim.Spec.MeasureSpec do
  @moduledoc """
  Specification for a metric to be measured during simulation.

  Measures are computed at each step (or at specified intervals) based on
  the collected agent states.

  ## Example

      %MeasureSpec{
        name: :total_wealth,
        every: 1,
        function: fn states ->
          states
          |> Map.values()
          |> Enum.map(& &1["wealth"])
          |> Enum.sum()
        end
      }
  """

  @type measure_fn :: (map() -> term())

  @type t :: %__MODULE__{
          name: atom(),
          every: pos_integer(),
          function: measure_fn()
        }

  @enforce_keys [:name, :function]
  defstruct [
    :name,
    :function,
    every: 1
  ]

  @doc """
  Creates a new MeasureSpec.

  ## Options

    - `:every` - Compute this metric every N steps (default: 1)
  """
  @spec new(atom(), measure_fn(), keyword()) :: t()
  def new(name, function, opts \\ []) when is_atom(name) and is_function(function, 1) do
    every = Keyword.get(opts, :every, 1)
    %__MODULE__{name: name, function: function, every: every}
  end
end
