# Time Interval Example

## Overview

Demonstrates **time_interval tick mode** where simulation steps advance based on wall-clock time rather than agent activity.

## What It Tests

- **Time interval tick mode** (`tick :time_interval, every: 5`)
- **Time-based sampling** - collect state every N seconds regardless of agent progress
- **Asynchronous agent work** - agents work at their own pace
- **Real-time monitoring** - regular snapshots for observation

## How It Works

```
t=0s:  Simulation starts, Step 1 begins
       Agents start working independently
t=5s:  Step 1 ends, metrics collected
       Step 2 begins
t=10s: Step 2 ends, metrics collected
       Step 3 begins
...
```

Agents work continuously. The simulation samples their state at regular intervals.

## Why This Example Matters

Time-based stepping is essential for:

- **Real-time simulations** - model systems that evolve over time
- **Monitoring dashboards** - regular updates regardless of agent activity
- **Long-running processes** - periodic checkpoints for recovery
- **Variable workloads** - some agents fast, some slow, sample them all equally

## Key Files

- `time_interval.sim` - Simulation definition
- `skills/worker.md` - Worker agent behavior

## Running

```bash
mix sim.run examples/time_interval/time_interval.sim
```

## Expected Output

```
Simulation completed!
  Final step: 6
  Status: completed

Final metrics:
  total_tasks: N
  tasks_per_worker: %{worker_1: X, worker_2: Y}
```

## Configuration

```elixir
tick :time_interval, every: 5  # Step every 5 seconds
steps 6                         # Run for 6 steps (30 seconds total)
```

## Comparison with Other Modes

| Mode | When to Use |
|------|-------------|
| `state_reports` | When step = "all agents have updated" |
| `turn_based` | When agents must coordinate turns |
| `time_interval` | When step = "N seconds elapsed" |
| `output_count` | When step = "N outputs generated" |

## Use Cases

### Real-Time Monitoring
```elixir
tick :time_interval, every: 60  # Sample every minute
```

### Periodic Checkpoints
```elixir
tick :time_interval, every: 300  # Checkpoint every 5 minutes
```

### Animation/Simulation
```elixir
tick :time_interval, every: 1  # Update every second for smooth visualization
```

## Design Notes

In time_interval mode:
- Agents work continuously without waiting for step signals
- Metrics capture whatever state exists at sample time
- Fast agents may have done more work than slow agents
- The simulation runs for `steps * every` seconds total
