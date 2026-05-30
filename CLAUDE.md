# SubzeroSim

Domain-agnostic simulation layer on top of subzero-swarms. Adds time (ticks), metrics collection, and halt conditions to agent swarms.

## Setup

```bash
# Copy .env from subzero-swarm (contains API keys)
cp ../subzero-swarm/.env .

# Source before running
source .env
```

## Quick Start

```elixir
# Load and run a simulation
{:ok, spec} = SubzeroSim.load("my_simulation.sim")
{:ok, swarm_name} = SubzeroSim.run(spec)
{:ok, results} = SubzeroSim.wait(swarm_name)

# Or run and collect metrics in one call
{:ok, %{status: :completed, final_step: 3, metrics: %{...}}} =
  SubzeroSim.Runner.run_and_collect(spec, steps: 3, timeout: 60_000)
```

Or use CLI:
```bash
mix sim run my_simulation.sim      # Run simulation
mix sim status                     # Check running simulations
mix sim pause <name>               # Pause a running simulation
mix sim resume <name>              # Resume a paused simulation
mix sim validate *.sim             # Validate files
mix sim compare sim1.sim sim2.sim  # Compare simulations
mix sim cleanup --completed        # Clean up finished simulations
mix sim.test                       # E2E test all examples
mix sim.test --validate-only       # Only validate syntax
mix sim.test --steps 5 --timeout 120000  # Custom steps & timeout
mix sim.test --mock script.json    # Use canned responses
```

## Architecture

```
.sim file → Parser → %SimSpec{} → Compiler → swarm config → subzero-swarms
                                     ↓
                              Injects Tick + Metrics objects
                              Auto-wires objects → :metrics
                              Per-agent workspace paths (counted roles)
```

## DSL Reference

```elixir
use SubzeroSim.DSL

simulation "name" do
  # Tick modes:
  tick :state_reports                    # Default: step when all agents reported
  tick :turn_based                       # Explicit coordination
  tick :turn_based, parallel: true       # All agents act simultaneously
  tick :turn_based, wait_for_objects: true  # Wait for objects to signal ready
  tick :time_interval, every: 60         # Every 60 seconds
  tick :output_count, every: 10          # Every 10 LLM outputs
  tick :pipeline, coordinator: :orchestrator  # Step only when coordinator sends advance_step

  # Configurable metrics retry timeout (passed through compiler to Metrics):
  tick :state_reports, retry_timeout: 30_000, max_retries: 10

  # Start triggers:
  start :immediate                       # Default
  start :on_ready                        # Wait for agents
  start {:delayed, 5}                    # After 5 seconds
  start :manual                          # CLI trigger

  steps 100                              # Max steps

  agent :role_name, count: 5, backend: :bwrap, model: "anthropic/claude-sonnet-4" do
    skill "skills/skill.md"
    config key: value
  end

  object :name, handler: MyModule, config: %{}

  connect :from, :to
  connect :from, :to, bidirectional: true
  connect :my_object, :metrics           # Can connect to system objects (:tick, :metrics, :gateway)
  connect :my_object, :tick

  measure :metric_name, fn states -> compute(states) end

  # Halt conditions:
  halt after: 100                                    # After N steps
  halt when: fn metrics -> metrics[:done] end        # When predicate true

  # Convergence/plateau detection:
  halt converged: [metric: :wealth, threshold: 100]  # When metric varies < threshold
  halt plateaued: [metric: :gini, threshold: 0.01]   # When change/step < threshold

  # Custom history-based halt:
  halt when_history: fn {metrics, history} ->
    case history[:loss] do
      series when length(series) >= 10 ->
        recent = Enum.take(series, -10) |> Enum.map(&elem(&1, 1))
        Enum.max(recent) - Enum.min(recent) < 0.001
      _ -> false
    end
  end
end
```

## Key Modules

- `SubzeroSim` - Main API
- `SubzeroSim.DSL` - DSL macros
- `SubzeroSim.Loader` - Loads .sim files
- `SubzeroSim.Validator` - Validates specs
- `SubzeroSim.Compiler` - Compiles to swarm configs
- `SubzeroSim.Runner` - Runs simulations (including `start_child/2`, `run_and_collect/2`, `pause/1`, `resume/1`)
- `SubzeroSim.Batch` - Parallel batch execution
- `SubzeroSim.Variant` - SimSpec modification helpers
- `SubzeroSim.Objects.Tick` - Step coordination
- `SubzeroSim.Objects.Metrics` - Metrics collection
- `SubzeroSim.Objects.Gateway` - Parent-child communication (auto-injected)
- `SubzeroSim.Store.*` - DETS-backed stores (cross-process persistence)
- `SubzeroSim.CLI.Output` - CLI formatting helpers

## Examples

Working examples in `examples/`:
- `hello_world` - Simple turn_based simulation
- `counter` - state_reports mode with metrics
- `ping_pong` - Custom object handler (Ball)
- `two_teams` - 8 agents with Scoreboard object
- `halt_conditions` - Custom halt predicates
- `parallel_vs_sequential/` - Parallel vs sequential turn modes
- `time_interval` - Steps advance every N seconds
- `output_count` - Steps advance after N total LLM outputs
- `nested_simple` - Parent-child simulation with Gateway
- `batch_variants` - Batch execution with Variant module
- `pause_resume` - Pause/resume demonstration

Run with: `mix sim run examples/hello_world/hello_world.sim`

## Nested Simulations

Parent simulations can spawn child simulations using `Runner.start_child/2`:

```elixir
# Start a child simulation with gateway injection
{:ok, child} = Runner.start_child(spec,
  parent: self(),
  initial_task: %{task: "do_work"},
  inject_to: :coordinator,      # Agent to receive initial_task
  collect_from: :coordinator    # Agent to collect final_result from
)

# Wait for completion (includes gateway_result)
{:ok, info} = Runner.wait_for_completion(child.name)
IO.inspect(info.gateway_result)  # Final result from child
```

Child agents send results via: `swarm-msg send gateway '{"action": "final_result", "data": {...}}'`

## Batch Execution

Run multiple simulations with concurrency control:

```elixir
# Run variants with concurrency limit
Batch.run_variants(base_spec, [
  fn spec -> Variant.set_agent_count(spec, :worker, 5) end,
  fn spec -> Variant.set_agent_count(spec, :worker, 10) end
], max_concurrent: 2)

# Run from files
Batch.run_files(["sim1.sim", "sim2.sim"], max_concurrent: 4)
```

## Variant Helpers

Modify SimSpec structs for parameter sweeps:

```elixir
spec
|> Variant.set_name("variant_001")
|> Variant.set_agent_count(:trader, 5)
|> Variant.set_model(:trader, "anthropic/claude-haiku")
|> Variant.update_config(:trader, %{risk: 0.8})
|> Variant.add_connection(:trader, :market)
|> Variant.set_steps(50)

# Generate N variants
Variant.generate(spec, 10, fn spec, i ->
  Variant.set_agent_count(spec, :worker, i + 1)
end)
```

## Message Protocol

### Tick → Metrics (init)
- `{"action": "start_step", "data": {"step": N}}` (state_reports mode)
- `{"action": "start_turn", "data": {"step": N}}` (turn_based parallel)

### Tick → Agents (turn_based sequential only)
- `{"action": "your_turn", "data": {"step": N}}`
- `{"action": "simulation_halted", "data": {"reason": "...", "step": N}}`

### Metrics → Agents (broadcast)
- `{"action": "new_step", "data": {"step": N}}` (state_reports mode)
- `{"action": "your_turn", "data": {"step": N}}` (turn_based parallel)

### Agents → Metrics
- `{"action": "state_report", "data": {"state": {...}}}`
- `{"action": "turn_complete"}` (turn_based mode)

### Coordinator → Tick (pipeline mode)
- `{"action": "advance_step"}` - Coordinator object signals tick to advance step

### Metrics → Tick
- `{"action": "step_complete"}`
- `{"action": "halt", "data": {"reason": "..."}}`

### Gateway (child simulations)
- `{"action": "simulation_started", "data": {"step": N}}` - From Tick on start
- `{"action": "initial_task", "data": {...}}` - Injected to agent
- `{"action": "final_result", "data": {...}}` - From agent to Gateway

### Pause/Resume
- `{"action": "pause"}` - Pause step advancement
- `{"action": "resume"}` - Resume step advancement
- `{"action": "simulation_paused", "data": {"step": N}}` - Broadcast on pause
- `{"action": "simulation_resumed", "data": {"step": N}}` - Broadcast on resume

### Object Busy/Ready (wait_for_objects mode)
- `{"action": "object_busy"}` - Object signals it's starting long-running work
- `{"action": "object_ready"}` - Object signals it's done with work
- Objects must send these to tick; topology auto-injected for wait_for_objects mode

## Testing

```bash
mix test                              # All tests (unit)
mix test test/subzero_sim/dsl_test.exs   # DSL tests only
mix sim.test                          # E2E tests on all examples
mix sim.test --validate-only          # Quick syntax check
mix sim.test --mock script.json       # E2E with canned responses (no API keys needed)
```

E2E test logs are saved to `.test-logs/` by default (one file per example, plus `summary.log`).

## Dependencies

- `subzeroclaw_swarm` (path: "../subzero-swarm")
- `jason` ~> 1.4
