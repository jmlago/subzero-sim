defmodule SubzeroSim.ChildHandle do
  @moduledoc """
  Handle struct for tracking child simulations.

  Contains all information needed to track and wait for a child simulation
  that was spawned by `Runner.start_child/2`.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          parent_pid: pid(),
          inject_to: atom() | nil,
          collect_from: atom() | nil,
          initial_task: map() | nil,
          started_at: DateTime.t()
        }

  @enforce_keys [:name, :parent_pid, :started_at]
  defstruct [
    :name,
    :parent_pid,
    :inject_to,
    :collect_from,
    :initial_task,
    :started_at
  ]

  @doc """
  Creates a new ChildHandle.
  """
  @spec new(String.t(), pid(), keyword()) :: t()
  def new(name, parent_pid, opts \\ []) do
    %__MODULE__{
      name: name,
      parent_pid: parent_pid,
      inject_to: Keyword.get(opts, :inject_to),
      collect_from: Keyword.get(opts, :collect_from),
      initial_task: Keyword.get(opts, :initial_task),
      started_at: DateTime.utc_now()
    }
  end
end
