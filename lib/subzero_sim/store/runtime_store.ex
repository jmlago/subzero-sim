defmodule SubzeroSim.Store.RuntimeStore do
  @moduledoc """
  DETS-backed store for simulation runtime status.

  Uses DETS (disk-based ETS) for cross-process persistence, allowing
  CLI commands like `mix sim status` to read state from running simulations.

  Tracks:
  - Simulation status (initializing, running, halted, completed)
  - Current step number
  - Halt reason (if halted)
  """

  @table :subzero_sim_runtime

  @type status :: :initializing | :running | :paused | :halted | :completed

  @doc """
  Ensures the DETS table exists.
  """
  @spec ensure_table() :: :ok
  def ensure_table do
    case :dets.info(@table) do
      :undefined ->
        dir =
          Application.get_env(:subzero_sim, :data_dir, "~/.subzeroclaw/runtime") |> Path.expand()

        File.mkdir_p!(dir)

        {:ok, @table} =
          :dets.open_file(@table,
            file: String.to_charlist(Path.join(dir, "simulations.dets")),
            type: :set,
            auto_save: 1000
          )

        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Initializes runtime tracking for a simulation.

  Options:
  - `:agent_names` - list of agent name atoms
  - `:max_steps` - maximum steps (or nil for unlimited)
  - `:mode` - tick mode atom
  - `:opts` - tick mode options map
  """
  @spec init_simulation(String.t(), keyword()) :: :ok
  def init_simulation(sim_name, opts \\ []) do
    ensure_table()
    :dets.insert(@table, {{sim_name, :status}, :initializing})
    :dets.insert(@table, {{sim_name, :step}, 0})
    :dets.insert(@table, {{sim_name, :halt_reason}, nil})
    :dets.insert(@table, {{sim_name, :started_at}, DateTime.utc_now()})
    :dets.insert(@table, {{sim_name, :agent_names}, Keyword.get(opts, :agent_names, [])})
    :dets.insert(@table, {{sim_name, :max_steps}, Keyword.get(opts, :max_steps)})
    :dets.insert(@table, {{sim_name, :mode}, Keyword.get(opts, :mode)})
    :dets.insert(@table, {{sim_name, :opts}, Keyword.get(opts, :opts, %{})})

    # Track simulation name for listing
    :dets.insert(@table, {{:sim_names, sim_name}, true})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Gets the status of a simulation.
  """
  @spec get_status(String.t()) :: status() | nil
  def get_status(sim_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, :status}) do
      [{_, status}] -> status
      [] -> nil
    end
  end

  @doc """
  Sets the status of a simulation.
  """
  @spec set_status(String.t(), status()) :: :ok
  def set_status(sim_name, status) do
    ensure_table()
    :dets.insert(@table, {{sim_name, :status}, status})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Gets the current step of a simulation.
  """
  @spec get_step(String.t()) :: non_neg_integer() | nil
  def get_step(sim_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, :step}) do
      [{_, step}] -> step
      [] -> nil
    end
  end

  @doc """
  Sets the current step of a simulation.
  """
  @spec set_step(String.t(), non_neg_integer()) :: :ok
  def set_step(sim_name, step) do
    ensure_table()
    :dets.insert(@table, {{sim_name, :step}, step})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Gets the halt reason of a simulation.
  """
  @spec get_halt_reason(String.t()) :: String.t() | nil
  def get_halt_reason(sim_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, :halt_reason}) do
      [{_, reason}] -> reason
      [] -> nil
    end
  end

  @doc """
  Sets the halt reason of a simulation.
  """
  @spec set_halt_reason(String.t(), String.t()) :: :ok
  def set_halt_reason(sim_name, reason) do
    ensure_table()
    :dets.insert(@table, {{sim_name, :halt_reason}, reason})
    :ok
  end

  @doc """
  Gets the start time of a simulation.
  """
  @spec get_started_at(String.t()) :: DateTime.t() | nil
  def get_started_at(sim_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, :started_at}) do
      [{_, time}] -> time
      [] -> nil
    end
  end

  @doc """
  Gets all runtime info for a simulation.
  """
  @spec get_info(String.t()) :: map() | nil
  def get_info(sim_name) do
    ensure_table()

    case get_status(sim_name) do
      nil ->
        nil

      status ->
        %{
          name: sim_name,
          status: status,
          step: get_step(sim_name),
          halt_reason: get_halt_reason(sim_name),
          started_at: get_started_at(sim_name),
          agent_names: get_field(sim_name, :agent_names, []),
          max_steps: get_field(sim_name, :max_steps),
          mode: get_field(sim_name, :mode),
          opts: get_field(sim_name, :opts, %{})
        }
    end
  end

  @doc """
  Lists all tracked simulations.
  """
  @spec list_simulations() :: [map()]
  def list_simulations do
    ensure_table()

    # Get all simulation names
    :dets.match(@table, {{:sim_names, :"$1"}, true})
    |> Enum.map(fn [name] -> name end)
    |> Enum.map(&get_info/1)
    |> Enum.reject(&is_nil/1)
  end

  defp get_field(sim_name, field, default \\ nil) do
    case :dets.lookup(@table, {sim_name, field}) do
      [{_, value}] -> value
      [] -> default
    end
  end

  @doc """
  Checks if a simulation is complete (halted or completed).
  """
  @spec complete?(String.t()) :: boolean()
  def complete?(sim_name) do
    get_status(sim_name) in [:halted, :completed]
  end

  @doc """
  Checks if a simulation is paused.
  """
  @spec paused?(String.t()) :: boolean()
  def paused?(sim_name) do
    get_status(sim_name) == :paused
  end

  @doc """
  Sets a simulation to paused status and stores the paused step.
  """
  @spec set_paused(String.t(), non_neg_integer()) :: :ok
  def set_paused(sim_name, step) do
    ensure_table()
    :dets.insert(@table, {{sim_name, :status}, :paused})
    :dets.insert(@table, {{sim_name, :paused_at_step}, step})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Gets the step at which the simulation was paused.
  """
  @spec get_paused_at_step(String.t()) :: non_neg_integer() | nil
  def get_paused_at_step(sim_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, :paused_at_step}) do
      [{_, step}] -> step
      [] -> nil
    end
  end

  @doc """
  Clears the paused status and resumes the simulation.
  """
  @spec clear_paused(String.t()) :: :ok
  def clear_paused(sim_name) do
    ensure_table()
    :dets.delete(@table, {sim_name, :paused_at_step})
    :dets.insert(@table, {{sim_name, :status}, :running})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Cleans up runtime data for a simulation.
  """
  @spec cleanup(String.t()) :: :ok
  def cleanup(sim_name) do
    ensure_table()
    :dets.delete(@table, {sim_name, :status})
    :dets.delete(@table, {sim_name, :step})
    :dets.delete(@table, {sim_name, :halt_reason})
    :dets.delete(@table, {sim_name, :started_at})
    :dets.delete(@table, {sim_name, :agent_names})
    :dets.delete(@table, {sim_name, :max_steps})
    :dets.delete(@table, {sim_name, :mode})
    :dets.delete(@table, {sim_name, :opts})
    :dets.delete(@table, {sim_name, :pause_requested})
    :dets.delete(@table, {sim_name, :resume_requested})
    :dets.delete(@table, {:sim_names, sim_name})
    :ok
  end

  # IPC Commands (for cross-process communication)

  @doc """
  Requests a pause via DETS (for cross-process IPC).
  The Tick object will poll for this and act accordingly.
  """
  @spec request_pause(String.t()) :: :ok
  def request_pause(sim_name) do
    ensure_table()
    :dets.insert(@table, {{sim_name, :pause_requested}, true})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Checks if a pause was requested and clears the flag.
  Returns true if pause was requested.
  """
  @spec consume_pause_request(String.t()) :: boolean()
  def consume_pause_request(sim_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, :pause_requested}) do
      [{_, true}] ->
        :dets.delete(@table, {sim_name, :pause_requested})
        :dets.sync(@table)
        true

      _ ->
        false
    end
  end

  @doc """
  Requests a resume via DETS (for cross-process IPC).
  The Tick object will poll for this and act accordingly.
  """
  @spec request_resume(String.t()) :: :ok
  def request_resume(sim_name) do
    ensure_table()
    :dets.insert(@table, {{sim_name, :resume_requested}, true})
    :dets.sync(@table)
    :ok
  end

  @doc """
  Checks if a resume was requested and clears the flag.
  Returns true if resume was requested.
  """
  @spec consume_resume_request(String.t()) :: boolean()
  def consume_resume_request(sim_name) do
    ensure_table()

    case :dets.lookup(@table, {sim_name, :resume_requested}) do
      [{_, true}] ->
        :dets.delete(@table, {sim_name, :resume_requested})
        :dets.sync(@table)
        true

      _ ->
        false
    end
  end
end
