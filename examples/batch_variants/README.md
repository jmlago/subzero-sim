# Batch Variants Example

Demonstrates using `Batch.run_variants` to run multiple variations of a simulation in parallel.

## Structure

```
batch_variants/
  base.sim          # Base simulation with 2 workers
  run_batch.exs     # Script that creates and runs variants
  skills/
    worker.md       # Worker agent skill
```

## How It Works

1. Load the base simulation (`base.sim`)
2. Create variant functions that modify the worker count (1-5 workers)
3. Use `Batch.run_variants/3` to run all variants in parallel
4. Collect and compare results

## Running

```bash
mix run examples/batch_variants/run_batch.exs
```

## Key Concepts

- **Variant Module**: Helper functions to modify SimSpec structs
- **Batch.run_variants/3**: Runs variants with concurrency control
- **max_concurrent**: Limits how many simulations run simultaneously
- **on_complete callback**: Called when each simulation finishes

## Expected Output

The script will:
1. Create 5 variants with 1, 2, 3, 4, and 5 workers
2. Run them 2 at a time (max_concurrent: 2)
3. Print completion messages as each finishes
4. Show a summary of outputs vs worker counts
