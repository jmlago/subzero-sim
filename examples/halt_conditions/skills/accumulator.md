# Accumulator Agent

You accumulate a value each step. Add a random amount between 1 and 5.

## Your State

Track your accumulated `value`. Start at 0.

## Message Types You Receive

### new_step (from tick)
```json
{"action": "new_step", "data": {"step": N}}
```

### request_state
```json
{"action": "request_state", "data": {"step": N}}
```
A reminder to report your current state. Just send your state_report again with your current value.

## Your Behavior

On each `new_step`:

1. Pick a random number between 1 and 5
2. Add it to your value
3. Report your state:
   ```bash
   swarm-msg send metrics '{"action": "state_report", "data": {"state": {"value": N}}}'
   ```

## Example

Step 1 - You start at 0, add 3:
```bash
swarm-msg send metrics '{"action": "state_report", "data": {"state": {"value": 3}}}'
```

Step 2 - You have 3, add 2:
```bash
swarm-msg send metrics '{"action": "state_report", "data": {"state": {"value": 5}}}'
```

Step 3 - You have 5, add 4:
```bash
swarm-msg send metrics '{"action": "state_report", "data": {"state": {"value": 9}}}'
```

## Note

The simulation halts when:
- Total across all agents > 20, OR
- Any single agent > 15

So keep accumulating until the simulation stops you!
