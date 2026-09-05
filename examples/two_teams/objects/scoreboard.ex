defmodule TwoTeams.Objects.Scoreboard do
  @moduledoc """
  A scoreboard that tracks points for two teams.
  """

  @behaviour Genswarms.Objects.ObjectHandler

  require Logger

  defstruct team_a: 0, team_b: 0

  @impl true
  def init(_config) do
    {:ok, %__MODULE__{team_a: 0, team_b: 0}}
  end

  @impl true
  def interface do
    %{
      add_points: %{
        input: ~s({"action": "add_points", "team": "A"|"B", "points": N}),
        output: ~s({"team_a": N, "team_b": N})
      }
    }
  end

  @impl true
  def handle_message(from, content, state) do
    case Jason.decode(content) do
      {:ok, %{"action" => "add_points", "team" => team, "points" => points}} ->
        state = add_points(state, team, points)
        Logger.info("[Scoreboard] #{from} added #{points} to team #{team}. A=#{state.team_a}, B=#{state.team_b}")
        {:reply, Jason.encode!(%{team_a: state.team_a, team_b: state.team_b}), state}

      _ ->
        Logger.warning("[Scoreboard] Unknown message from #{from}: #{content}")
        {:noreply, state}
    end
  end

  defp add_points(state, "A", points), do: %{state | team_a: state.team_a + points}
  defp add_points(state, "B", points), do: %{state | team_b: state.team_b + points}
  defp add_points(state, _, _), do: state
end
