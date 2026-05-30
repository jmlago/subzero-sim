# Counter Example

## Overview

Multiple counter agents independently increment their values, demonstrating **state_reports mode** with **role-based agent scaling**.

## What It Tests

- **State reports tick mode** (`tick :state_reports`) - step advances when all agents report state
- **Role scaling** (`count: 3`) - creates counter_1, counter_2, counter_3 from single role definition
- **Independent agent operation** - agents work at their own pace
- **Aggregate metrics** - computing totals and maximums across all agents
- **Retry mechanism** - handles unresponsive agents gracefully

## How It Works

```
Step 1:
  1. Tick broadcasts `new_step` to all agents
  2. Each counter independently:
     - Increments its count
     - Reports state to metrics
  3. When all agents report (or timeout), step completes
  4. Metrics computed: total_count, max_count

Step 2:
  (repeat)
```

## Why This Example Matters

State reports mode is the default and most flexible:

- **No coordination overhead** - agents work independently
- **Natural for parallel workloads** - each agent processes at its own speed
- **Handles variable response times** - retry mechanism ensures progress
- **Good for monitoring** - regular state snapshots without interrupting work

## Key Files

- `counter.sim` - Simulation definition
- `skills/counter.md` - Counter agent behavior

## Running

```bash
mix sim.run examples/counter/counter.sim
```

## Expected Output

```
Simulation completed!
  Final step: 10
  Status: completed

Final metrics:
  total_count: N   # Sum of all counter values
  max_count: M     # Highest individual counter
```

## Configuration

The simulation defines:

```elixir
agent :counter, count: 3  # Creates 3 counter agents
```

This expands to: `counter_1`, `counter_2`, `counter_3`

Each agent has:
- Initial config: `count: 0`
- Behavior: increment by 1-3 each step, report state

## Metrics

| Metric | Description |
|--------|-------------|
| `total_count` | Sum of all agents' count values |
| `max_count` | Highest count among all agents |

## Resilience

The simulation handles unresponsive agents:

1. **Timeout** (5 seconds) - if agent doesn't report, retry
2. **Retries** (3 attempts) - broadcast `request_state` to remind agents
3. **Partial completion** - proceed with available data after max retries

This ensures the simulation always makes progress even with unreliable agents.
