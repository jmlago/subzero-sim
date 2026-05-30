defmodule SubzeroSim.Spec.TickConfig do
  @moduledoc """
  Configuration for the Tick object that coordinates simulation steps.

  ## Tick Modes

  - `:state_reports` (default) - Step advances when all agents have reported state to Metrics.
    Simplest mode where agents work at their own pace.

  - `:turn_based` - Explicit your_turn/turn_complete coordination.
    Sequential by default, or parallel if `opts[:parallel]` is true.

  - `:time_interval` - Step advances every N seconds of real time.
    Requires `opts[:every]` to be set (in seconds).

  - `:output_count` - Step advances after N total LLM outputs.
    Requires `opts[:every]` to be set (count of outputs).

  - `:pipeline` - Step advances only when a coordinator object sends `advance_step`.
    Agents still send state_reports for metrics, but they don't gate step progression.
    Requires `opts[:coordinator]` to specify which object controls advancement.
  """

  @type mode :: :state_reports | :turn_based | :time_interval | :output_count | :pipeline

  @type t :: %__MODULE__{
          mode: mode(),
          opts: map()
        }

  defstruct mode: :state_reports,
            opts: %{}

  @doc """
  Creates a new TickConfig with the given mode and options.
  """
  @spec new(mode(), keyword() | map()) :: t()
  def new(mode, opts \\ %{}) do
    opts = if is_list(opts), do: Map.new(opts), else: opts
    %__MODULE__{mode: mode, opts: opts}
  end

  @doc """
  Validates that required options are present for the mode.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{mode: :time_interval, opts: opts}) do
    if Map.has_key?(opts, :every) and is_number(opts[:every]) and opts[:every] > 0 do
      :ok
    else
      {:error, ":time_interval mode requires :every option (positive number of seconds)"}
    end
  end

  def validate(%__MODULE__{mode: :output_count, opts: opts}) do
    if Map.has_key?(opts, :every) and is_integer(opts[:every]) and opts[:every] > 0 do
      :ok
    else
      {:error, ":output_count mode requires :every option (positive integer)"}
    end
  end

  def validate(%__MODULE__{mode: mode}) when mode in [:state_reports, :turn_based] do
    :ok
  end

  def validate(%__MODULE__{mode: :pipeline, opts: opts}) do
    if Map.has_key?(opts, :coordinator) and is_atom(opts[:coordinator]) do
      :ok
    else
      {:error, ":pipeline mode requires :coordinator option (atom naming the coordinator object)"}
    end
  end

  def validate(%__MODULE__{mode: mode}) do
    {:error, "Invalid tick mode: #{inspect(mode)}"}
  end
end
