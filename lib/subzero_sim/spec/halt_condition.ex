defmodule SubzeroSim.Spec.HaltCondition do
  @moduledoc """
  Specification for a condition that halts the simulation.

  ## Condition Types

  - `:after_steps` - Halt after N steps have completed.

  - `:when_predicate` - Halt when a predicate function returns true.
    Predicate receives the current metrics map.

  - `:when_history` - Halt when a predicate on metric history returns true.
    Predicate receives `{current_metrics, history}` where history is a map
    of metric_name => [{step, value}, ...].

  - `:metric_converged` - Halt when a metric hasn't changed significantly
    over a window of steps. Checks if max - min < threshold over the window.

  - `:metric_plateaued` - Halt when a metric's rate of change falls below
    a threshold. Computes average absolute change per step over a window.

  ## Examples

      # Halt after 100 steps
      %HaltCondition{type: :after_steps, value: 100}

      # Halt when total wealth exceeds 1 million
      %HaltCondition{
        type: :when_predicate,
        value: fn metrics -> metrics[:total_wealth] > 1_000_000 end
      }

      # Halt when wealth has converged (varies by < 100 over 10 steps)
      %HaltCondition{
        type: :metric_converged,
        value: %{metric: :total_wealth, window: 10, threshold: 100}
      }

      # Halt when gini coefficient is plateauing (changing < 0.01 per step)
      %HaltCondition{
        type: :metric_plateaued,
        value: %{metric: :gini, window: 5, threshold: 0.01}
      }

      # Custom convergence with full history access
      %HaltCondition{
        type: :when_history,
        value: fn {metrics, history} ->
          case history[:entropy] do
            nil -> false
            series when length(series) >= 10 ->
              recent = Enum.take(series, -10) |> Enum.map(&elem(&1, 1))
              Enum.max(recent) - Enum.min(recent) < 0.001
            _ -> false
          end
        end
      }
  """

  @type condition_type ::
          :after_steps
          | :when_predicate
          | :when_history
          | :metric_converged
          | :metric_plateaued

  @type predicate_fn :: (map() -> boolean())
  @type history_predicate_fn :: ({map(), map()} -> boolean())

  @type convergence_opts :: %{
          metric: atom(),
          window: pos_integer(),
          threshold: number()
        }

  @type condition_value ::
          pos_integer()
          | predicate_fn()
          | history_predicate_fn()
          | convergence_opts()

  @type t :: %__MODULE__{
          type: condition_type(),
          value: condition_value()
        }

  @enforce_keys [:type, :value]
  defstruct [:type, :value]

  @doc """
  Creates a halt condition that triggers after N steps.
  """
  @spec after_steps(pos_integer()) :: t()
  def after_steps(n) when is_integer(n) and n > 0 do
    %__MODULE__{type: :after_steps, value: n}
  end

  @doc """
  Creates a halt condition that triggers when a predicate returns true.
  The predicate receives the current metrics map.
  """
  @spec when_predicate(predicate_fn()) :: t()
  def when_predicate(fun) when is_function(fun, 1) do
    %__MODULE__{type: :when_predicate, value: fun}
  end

  @doc """
  Creates a halt condition with access to metric history.
  The predicate receives `{current_metrics, history}` where history is
  a map of metric_name => [{step, value}, ...] sorted by step ascending.
  """
  @spec when_history(history_predicate_fn()) :: t()
  def when_history(fun) when is_function(fun, 1) do
    %__MODULE__{type: :when_history, value: fun}
  end

  @doc """
  Creates a halt condition that triggers when a metric has converged.

  Convergence is defined as: over the last `window` steps, the difference
  between max and min values is less than `threshold`.

  ## Options
    - `:metric` - The metric name (atom)
    - `:window` - Number of recent steps to check (default: 10)
    - `:threshold` - Maximum allowed range for convergence (required)
  """
  @spec metric_converged(atom(), keyword()) :: t()
  def metric_converged(metric, opts) when is_atom(metric) do
    window = Keyword.get(opts, :window, 10)
    threshold = Keyword.fetch!(opts, :threshold)

    %__MODULE__{
      type: :metric_converged,
      value: %{metric: metric, window: window, threshold: threshold}
    }
  end

  @doc """
  Creates a halt condition that triggers when a metric has plateaued.

  Plateau is defined as: the average absolute change per step over the
  last `window` steps is less than `threshold`.

  ## Options
    - `:metric` - The metric name (atom)
    - `:window` - Number of recent steps to check (default: 10)
    - `:threshold` - Maximum allowed average change per step (required)
  """
  @spec metric_plateaued(atom(), keyword()) :: t()
  def metric_plateaued(metric, opts) when is_atom(metric) do
    window = Keyword.get(opts, :window, 10)
    threshold = Keyword.fetch!(opts, :threshold)

    %__MODULE__{
      type: :metric_plateaued,
      value: %{metric: metric, window: window, threshold: threshold}
    }
  end

  @doc """
  Evaluates the halt condition.

  For conditions that need history, pass it as the fourth argument.
  History should be a map of metric_name => [{step, value}, ...].
  """
  @spec evaluate(t(), pos_integer(), map(), map()) :: boolean()
  def evaluate(condition, step, metrics, history \\ %{})

  def evaluate(%__MODULE__{type: :after_steps, value: max_steps}, current_step, _metrics, _history) do
    current_step >= max_steps
  end

  def evaluate(%__MODULE__{type: :when_predicate, value: predicate}, _step, metrics, _history) do
    predicate.(metrics)
  end

  def evaluate(%__MODULE__{type: :when_history, value: predicate}, _step, metrics, history) do
    predicate.({metrics, history})
  end

  def evaluate(%__MODULE__{type: :metric_converged, value: opts}, _step, _metrics, history) do
    %{metric: metric, window: window, threshold: threshold} = opts

    case Map.get(history, metric, []) do
      series when length(series) >= window ->
        recent_values =
          series
          |> Enum.take(-window)
          |> Enum.map(&elem(&1, 1))
          |> Enum.filter(&is_number/1)

        if length(recent_values) >= window do
          range = Enum.max(recent_values) - Enum.min(recent_values)
          range < threshold
        else
          false
        end

      _ ->
        false
    end
  end

  def evaluate(%__MODULE__{type: :metric_plateaued, value: opts}, _step, _metrics, history) do
    %{metric: metric, window: window, threshold: threshold} = opts

    case Map.get(history, metric, []) do
      series when length(series) >= window ->
        recent_values =
          series
          |> Enum.take(-window)
          |> Enum.map(&elem(&1, 1))
          |> Enum.filter(&is_number/1)

        if length(recent_values) >= 2 do
          # Calculate average absolute change per step
          changes =
            recent_values
            |> Enum.chunk_every(2, 1, :discard)
            |> Enum.map(fn [a, b] -> abs(b - a) end)

          avg_change = Enum.sum(changes) / length(changes)
          avg_change < threshold
        else
          false
        end

      _ ->
        false
    end
  end
end
