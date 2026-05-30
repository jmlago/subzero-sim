# Ping Pong Example

## Overview

A classic ping-pong game between two agents demonstrating **turn-based sequential coordination**.

## What It Tests

- **Turn-based tick mode** (`tick :turn_based`)
- **Sequential agent execution** - agents take turns one at a time
- **Turn protocol**: `your_turn` → agent acts → `turn_complete`
- **Direct agent-to-agent communication** via `connect :ping, :pong, bidirectional: true`
- **State reporting** during turns

## How It Works

```
Step 1:
  1. Tick sends `your_turn` to ping
  2. Ping: sends ping to pong, reports state, signals turn_complete
  3. Tick sends `your_turn` to pong
  4. Pong: sends pong to ping, reports state, signals turn_complete
  5. Round complete → Metrics collected → Step advances

Step 2:
  (repeat)
```

## Why This Example Matters

Turn-based coordination is essential for:

- **Games** where players take alternating turns
- **Negotiations** where parties respond to each other sequentially
- **Workflows** with strict ordering requirements
- **Debugging** - easier to trace agent behavior when only one acts at a time

## Key Files

- `ping_pong.sim` - Simulation definition
- `skills/ping.md` - Ping agent behavior
- `skills/pong.md` - Pong agent behavior

## Running

```bash
mix sim.run examples/ping_pong/ping_pong.sim
```

## Expected Output

```
Simulation completed!
  Final step: 5
  Status: completed

Final metrics:
  total_volleys: N  # Sum of both agents' volley counts
```

## Design Notes

### Why No Ball Object?

An earlier design included a Ball object that bounced messages between players. This was removed because:

1. **Conflicts with turn-based mode** - The Ball would bounce messages immediately, ignoring turn coordination
2. **Unnecessary complexity** - In turn-based games, Tick already coordinates who acts when
3. **Agent-to-agent communication works** - Agents can send directly to each other

A Ball object would make sense in a `state_reports` or real-time mode where agents act freely and the ball tracks game state independently.

### Handling LLM Behavior

LLMs sometimes generate multiple responses in sequence. The example includes:

1. **Explicit skill instructions** - "Only act on `your_turn`", "STOP after turn_complete"
2. **Duplicate protection in Tick** - Ignores repeated `turn_complete` from same agent

This makes the simulation robust against unpredictable LLM output patterns.
