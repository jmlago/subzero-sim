# Halt Conditions Example

## Overview

Demonstrates **dynamic halt conditions** based on computed metrics, allowing simulations to stop when specific criteria are met rather than running for a fixed number of steps.

## What It Tests

- **Predicate-based halt conditions** (`halt when: fn metrics -> ... end`)
- **Multiple halt criteria** - simulation stops when ANY condition is met
- **Metric-driven termination** - halt based on computed values, not just step count
- **Early termination** - efficient resource usage by stopping when goals are reached

## How It Works

```elixir
# Halt when total across all agents exceeds 20
halt when: fn metrics -> (metrics[:total] || 0) > 20 end

# Halt when any single agent exceeds 15
halt when: fn metrics -> (metrics[:max_value] || 0) > 15 end
```

The simulation runs until:
1. Total accumulated value > 20, OR
2. Any single agent's value > 15, OR
3. Maximum steps reached (fallback)

## Why This Example Matters

Predicate-based halting is essential for:

- **Convergence detection** - stop when a model stabilizes
- **Goal achievement** - stop when agents reach an objective
- **Resource limits** - stop when a budget is exhausted
- **Safety bounds** - stop if metrics enter dangerous ranges
- **Efficiency** - don't waste compute on unnecessary steps

## Key Files

- `halt_conditions.sim` - Simulation with halt predicates
- `skills/accumulator.md` - Agent that accumulates random values

## Running

```bash
mix sim.run examples/halt_conditions/halt_conditions.sim
```

## Expected Output

```
Simulation halted: predicate_met

Simulation completed!
  Final step: N
  Status: halted
  Reason: predicate_met

Final metrics:
  total: X      # > 20 when halted
  max_value: Y  # > 15 when halted
```

## Halt Condition Types

SubzeroSim supports several halt condition types:

| Type | Syntax | Description |
|------|--------|-------------|
| `after` | `halt after: 10` | Stop after N steps |
| `when` (predicate) | `halt when: fn metrics -> ... end` | Stop when function returns true |
| `when` (history) | `halt when: fn metrics, history -> ... end` | Access metric history for trend analysis |

## Use Cases

### Convergence Detection
```elixir
halt when: fn metrics, history ->
  recent = history[:loss] |> Enum.take(-5) |> Enum.map(&elem(&1, 1))
  Enum.max(recent) - Enum.min(recent) < 0.01
end
```

### Goal Achievement
```elixir
halt when: fn metrics -> metrics[:score] >= 100 end
```

### Safety Bounds
```elixir
halt when: fn metrics -> metrics[:error_rate] > 0.5 end
```

## Design Notes

Multiple halt conditions are evaluated with OR logic - the simulation stops when ANY condition is satisfied. This allows combining:

- Safety limits (must stop if exceeded)
- Success criteria (can stop if achieved)
- Maximum runtime (fallback guarantee)
