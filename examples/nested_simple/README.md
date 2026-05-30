# Nested Simple Example

Demonstrates basic parent-child simulation communication using the Gateway object.

## Structure

```
nested_simple/
  parent.sim              # Parent simulation
  child.sim               # Child simulation
  objects/
    evaluator.ex          # Object that launches child simulation
  skills/
    orchestrator.md       # Parent agent skill
    coordinator.md        # Child agent skill
```

## How It Works

1. Parent simulation starts with one `orchestrator` agent
2. On its turn, the orchestrator sends an `evaluate` request to the `evaluator` object
3. The evaluator:
   - Loads and starts the child simulation using `Runner.start_child/2`
   - The child gets a Gateway object auto-injected
   - Initial task is sent to the child's `coordinator` agent
4. Child simulation runs for 3 steps, with the coordinator doing "work"
5. When the child halts, the coordinator sends `final_result` to the Gateway
6. Gateway stores the result and notifies the parent process
7. The evaluator receives the result and returns it to the orchestrator

## Running

```bash
mix sim run examples/nested_simple/parent.sim
```

## Key Concepts

- **Gateway Object**: Auto-injected into child simulations, handles parent-child communication
- **start_child/2**: Launches a child simulation with gateway injection
- **initial_task**: Task data injected to a specific agent when child starts
- **final_result**: Result collected from a specific agent when child completes
