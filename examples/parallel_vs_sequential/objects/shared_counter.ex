defmodule ParallelTest.Objects.SharedCounter do
  @moduledoc """
  A shared counter to demonstrate parallel vs sequential behavior.

  In parallel mode: All agents increment simultaneously, potentially
  reading the same value before any writes complete.

  In sequential mode: Each agent sees the result of the previous
  agent's increment.
  """

  @behaviour Genswarms.Objects.ObjectHandler

  require Logger

  defstruct counter: 0, writes: []

  @impl true
  def init(_config) do
    {:ok, %__MODULE__{counter: 0, writes: []}}
  end

  @impl true
  def interface do
    %{
      increment: %{
        input: ~s({"action": "increment"}),
        output: ~s({"previous": N, "new": N})
      }
    }
  end

  @impl true
  def handle_message(from, content, state) do
    case Jason.decode(content) do
      {:ok, %{"action" => "increment"}} ->
        previous = state.counter
        new_counter = state.counter + 1
        state = %{state |
          counter: new_counter,
          writes: state.writes ++ [{from, previous, new_counter}]
        }
        Logger.info("[SharedCounter] #{from}: #{previous} -> #{new_counter}")
        {:reply, Jason.encode!(%{previous: previous, new: new_counter}), state}

      _ ->
        {:noreply, state}
    end
  end
end
