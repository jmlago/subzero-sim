# Pause/Resume Example

Demonstrates the pause and resume functionality for simulations.

## Structure

```
pause_resume/
  long_running.sim    # Simulation that runs for 20 steps (2s intervals)
  skills/
    counter.md        # Counter agent skill
```

## How It Works

1. The simulation uses `time_interval` mode with 2-second steps
2. It runs for up to 20 steps
3. You can pause and resume it using CLI commands

## Running

### Terminal 1: Start the simulation in background

```bash
mix sim run examples/pause_resume/long_running.sim &
```

### Terminal 2: Control the simulation

```bash
# Wait a few seconds for it to start
sleep 5

# Check status
mix sim status
# Should show "running at step ~2"

# Pause the simulation
mix sim pause pause_test

# Check status again
mix sim status
# Should show "paused at step N"

# Wait and verify it's still paused
sleep 5
mix sim status
# Should show same step number

# Resume the simulation
mix sim resume pause_test

# Watch it continue
mix sim status
# Should show "running" and advancing steps
```

## Key Concepts

- **pause**: Stops step advancement but keeps simulation in memory
- **resume**: Continues from the paused step
- **time_interval mode**: Steps advance based on wall clock time
- **Paused state**: Stored in RuntimeStore for CLI access

## CLI Commands

- `mix sim pause <name>` - Pause a running simulation
- `mix sim resume <name>` - Resume a paused simulation
- `mix sim status` - Shows pause state in status display
