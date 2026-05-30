# Output Count Example

## Overview

Demonstrates **output_count tick mode** where simulation steps advance based on the total number of LLM outputs rather than time or state reports.

## What It Tests

- **Output count tick mode** (`tick :output_count, every: 3`)
- **Work-based stepping** - steps advance after N total outputs
- **Variable agent productivity** - measures how much each agent contributes
- **Fair resource accounting** - tracks actual work done, not just time elapsed

## How It Works

```
Output 1: producer_1 generates output
Output 2: producer_2 generates output
Output 3: producer_1 generates output
→ Step advances (3 outputs reached)
→ Metrics collected

Output 4: producer_2 generates output
Output 5: producer_1 generates output
Output 6: producer_2 generates output
→ Step advances
...
```

## Why This Example Matters

Output-based stepping is useful for:

- **Cost accounting** - steps correlate with actual LLM API calls
- **Fair comparison** - compare simulations by work done, not wall time
- **Batch processing** - process N items then checkpoint
- **Rate limiting** - control simulation pace based on output volume

## Key Files

- `output_count.sim` - Simulation definition
- `skills/producer.md` - Producer agent behavior

## Running

```bash
mix sim.run examples/output_count/output_count.sim
```

## Expected Output

```
Simulation completed!
  Final step: 5
  Status: halted
  Reason: after_5_steps

Final metrics:
  total_outputs: N
  outputs_per_agent: %{producer_1: X, producer_2: Y}
```

## Configuration

```elixir
tick :output_count, every: 3  # Step every 3 outputs
```

This means:
- After 3 total LLM outputs across all agents, step 1 completes
- After 6 total outputs, step 2 completes
- And so on...

## Metrics

| Metric | Description |
|--------|-------------|
| `total_outputs` | Total LLM outputs generated |
| `outputs_per_agent` | Map of agent → output count |

## Comparison with Other Modes

| Mode | Step Advances When |
|------|-------------------|
| `state_reports` | All agents report state |
| `turn_based` | All agents complete turns |
| `time_interval` | N seconds elapse |
| `output_count` | N total outputs generated |

## Use Cases

### API Cost Control
```elixir
tick :output_count, every: 100  # Checkpoint every 100 API calls
```

### Fair Benchmarking
Compare different agent strategies by total work done, not elapsed time.

### Batch Processing
```elixir
tick :output_count, every: 50  # Process 50 items per step
```
