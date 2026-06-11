defmodule PingPong.Objects.Ball do
  @moduledoc """
  A simple ball object that bounces between ping and pong agents.
  """

  @behaviour Genswarms.Objects.ObjectHandler

  require Logger

  defstruct volley_count: 0

  @impl true
  def init(_config) do
    {:ok, %__MODULE__{volley_count: 0}}
  end

  @impl true
  def interface do
    %{
      ping: %{
        input: ~s({"action": "ping"}),
        output: ~s({"action": "pong", "volley": N})
      },
      pong: %{
        input: ~s({"action": "pong"}),
        output: ~s({"action": "ping", "volley": N})
      }
    }
  end

  @impl true
  def handle_message(from, content, state) do
    case Jason.decode(content) do
      {:ok, %{"action" => "ping"}} ->
        state = %{state | volley_count: state.volley_count + 1}
        Logger.info("[Ball] Received ping from #{from}, volley #{state.volley_count}")
        {:send, :pong, Jason.encode!(%{action: "pong", volley: state.volley_count}), state}

      {:ok, %{"action" => "pong"}} ->
        state = %{state | volley_count: state.volley_count + 1}
        Logger.info("[Ball] Received pong from #{from}, volley #{state.volley_count}")
        {:send, :ping, Jason.encode!(%{action: "ping", volley: state.volley_count}), state}

      _ ->
        Logger.warning("[Ball] Unknown message from #{from}: #{content}")
        {:noreply, state}
    end
  end
end
