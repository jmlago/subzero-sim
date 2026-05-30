# Parallel vs Sequential Example

## Overview

Two simulations comparing **parallel** and **sequential** turn-based execution modes, demonstrating how the same agents behave differently under different coordination strategies.

## What It Tests

- **Parallel turn-based mode** (`tick :turn_based, parallel: true`)
- **Sequential turn-based mode** (`tick :turn_based, parallel: false`)
- **Shared object access** - multiple agents interacting with same object
- **Coordination patterns** - how turn ordering affects outcomes

## How It Works

### Sequential Mode (sequential.sim)
```
Step 1:
  1. Tick sends your_turn to writer_1
  2. writer_1 acts, signals turn_complete
  3. Tick sends your_turn to writer_2
  4. writer_2 acts, signals turn_complete
  5. Tick sends your_turn to writer_3
  6. writer_3 acts, signals turn_complete
  7. Round complete → Step advances
```

### Parallel Mode (parallel.sim)
```
Step 1:
  1. Tick broadcasts your_turn to ALL writers
  2. writer_1, writer_2, writer_3 act SIMULTANEOUSLY
  3. All signal turn_complete
  4. Round complete → Step advances
```

## Why This Example Matters

Understanding parallel vs sequential is critical for:

- **Correctness** - some algorithms require sequential access
- **Performance** - parallel is faster but may have race conditions
- **Fairness** - sequential gives each agent uncontested access
- **Realism** - model real-world systems with different concurrency models

## Key Files

- `parallel.sim` - Parallel execution simulation
- `sequential.sim` - Sequential execution simulation
- `skills/writer.md` - Writer agent behavior
- `objects/shared_counter.ex` - Shared counter object

## Running

```bash
# Run sequential version
mix sim.run examples/parallel_vs_sequential/sequential.sim

# Run parallel version
mix sim.run examples/parallel_vs_sequential/parallel.sim
```

## Expected Differences

| Aspect | Sequential | Parallel |
|--------|------------|----------|
| Speed | Slower (agents wait) | Faster (all act together) |
| Object access | Uncontested | Potential conflicts |
| Turn order | Deterministic | Undefined |
| Suitable for | Negotiations, games | Independent tasks |

## Use Cases

### Sequential
- Turn-based games (chess, negotiations)
- Ordered workflows
- When agents need to see previous agent's action

### Parallel
- Independent workers
- Embarrassingly parallel tasks
- When agents don't need to coordinate

## Configuration

```elixir
# Sequential (default)
tick :turn_based
# or explicitly:
tick :turn_based, parallel: false

# Parallel
tick :turn_based, parallel: true
```

## Shared Object Pattern

Both simulations include a shared counter object:

```elixir
object :shared_counter, handler: ParallelTest.Objects.SharedCounter
connect :writer, :shared_counter, bidirectional: true
```

This allows testing how concurrent access behaves differently in each mode.
