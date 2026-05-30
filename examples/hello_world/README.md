# Hello World Example

## Overview

The simplest possible simulation - agents that greet each other. A minimal example to verify the framework is working.

## What It Tests

- **Basic simulation structure** - minimal viable simulation
- **Turn-based mode** with multiple agents of same role
- **Agent instantiation** from role with `count: 2`
- **Framework connectivity** - agents can send messages

## How It Works

```elixir
simulation "hello_world" do
  tick :turn_based
  start :immediate

  agent :greeter, count: 2, backend: :bwrap, model: "minimax/minimax-m2.7", preset: :base do
    skill "skills/greeter.md"
  end

  halt after: 3
end
```

Two greeter agents take turns for 3 steps, each saying hello on their turn.

## Why This Example Matters

Every framework needs a "hello world":

- **Smoke test** - verify installation and configuration
- **Learning** - understand the minimal structure
- **Template** - starting point for new simulations
- **Debugging** - isolate issues to the simplest case

## Key Files

- `hello_world.sim` - Simulation definition
- `skills/greeter.md` - Greeter agent behavior

## Running

```bash
mix sim.run examples/hello_world/hello_world.sim
```

## Expected Output

```
Simulation completed!
  Final step: 3
  Status: completed
```

## Anatomy of a Minimal Simulation

```elixir
use SubzeroSim.DSL

simulation "name" do
  tick :mode           # How steps advance
  start :immediate     # When to start

  agent :role do       # Define agent behavior
    skill "path.md"
  end

  halt after: N        # When to stop
end
```

## Next Steps

After hello_world works, try:

1. **counter** - Multiple agents, state tracking, metrics
2. **ping_pong** - Agent-to-agent communication
3. **halt_conditions** - Dynamic stopping criteria
