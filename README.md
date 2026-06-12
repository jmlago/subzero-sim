# SubzeroSim

A domain-agnostic simulation layer on top of [genswarms](https://github.com/genlayerlabs/genswarms). Adds time (ticks), metrics collection, and halt conditions to agent swarms.

## Features

- **DSL for simulations** - Write `.sim` files with a clean Elixir DSL
- **Multiple tick modes** - State reports, turn-based, time intervals, output counting, or pipeline
- **Metrics collection** - Define custom metrics computed at each step
- **Flexible halt conditions** - Stop after N steps, on predicates, or when metrics converge/plateau
- **Mix tasks** - Run, validate, compare, and e2e test simulations from the command line
- **Programmatic API** - `SubzeroSim.Runner.run_and_collect/2` for running sims and collecting metrics in code

## Installation

Add `subzero_sim` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:subzero_sim, path: "../subzero-sim"}
  ]
end
```

## Quick Start

### Setup

1. Copy `.env` from genswarms (contains API keys):
   ```bash
   cp ../genswarms/.env .
   ```

2. Source the environment before running:
   ```bash
   source .env
   ```

### Create a Simulation

Create a simulation file `my_sim.sim`:

```elixir
use SubzeroSim.DSL

simulation "my_simulation" do
  tick :state_reports
  steps 100

  agent :worker, count: 5, backend: :bwrap, model: "anthropic/claude-sonnet-4" do
    skill "skills/worker.md"
    config energy: 100
  end

  agent :coordinator, backend: :bwrap do
    skill "skills/coordinator.md"
  end

  connect :worker, :coordinator, bidirectional: true

  measure :total_energy, fn states ->
    states |> Map.values() |> Enum.map(&(&1["energy"] || 0)) |> Enum.sum()
  end

  halt after: 100
  halt converged: [metric: :total_energy, threshold: 10, window: 10]
end
```

Run it:

```bash
mix sim run my_sim.sim
```

Or programmatically:

```elixir
{:ok, spec} = SubzeroSim.load("my_sim.sim")
{:ok, swarm_name} = SubzeroSim.run(spec)
{:ok, results} = SubzeroSim.wait(swarm_name)
```

Run and collect metrics in one call:

```elixir
{:ok, spec} = SubzeroSim.load("my_sim.sim")
{:ok, %{status: :completed, final_step: 3, metrics: %{...}}} =
  SubzeroSim.Runner.run_and_collect(spec, steps: 3, timeout: 60_000)
```

## DSL Reference

### Simulation Block

```elixir
simulation "name" do
  # configuration...
end
```

### Tick Modes

Control how simulation steps advance:

```elixir
tick :state_reports              # Default: step when all agents report state
tick :turn_based                 # Explicit your_turn/turn_complete coordination
tick :turn_based, parallel: true # All agents act simultaneously per step
tick :time_interval, every: 60   # Step every 60 seconds of real time
tick :output_count, every: 10    # Step every 10 LLM outputs
tick :pipeline, coordinator: :orchestrator  # Step only when coordinator sends advance_step

# Configurable metrics retry timeout (state_reports mode)
tick :state_reports, retry_timeout: 30_000, max_retries: 10
```

### Start Triggers

Control when the simulation begins:

```elixir
start :immediate        # Start immediately (default)
start :on_ready         # Wait for all agents to signal ready
start {:delayed, 5}     # Start after 5 seconds
start :manual           # Wait for explicit start command
```

### Agents

Define agent roles:

```elixir
# Simple agent (defaults to :bwrap backend)
agent :worker

# Agent with options
agent :trader, count: 5, backend: :bwrap, model: "anthropic/claude-sonnet-4"

# Agent with configuration block
agent :trader, count: 5, backend: :bwrap do
  skill "skills/trader.md"
  config wealth: 1000, risk_tolerance: 0.5
end

# Using Docker backend
agent :coder, backend: {:docker, "szc-agent-code:latest"} do
  skill "skills/coder.md"
end
```

Options:
- `:count` - Number of agents to create (default: 1)
- `:backend` - Backend: `:bwrap` (default), `{:docker, image}`, `:local`
- `:model` - Model name (e.g., "anthropic/claude-sonnet-4", "minimax/minimax-m2.7")
- `:endpoint` - Custom API endpoint
- `:preset` - Tool preset for sandbox (`:base`, `:web`, `:code`, etc.)

### Objects

Define non-agentic objects:

```elixir
object :orderbook, handler: MyApp.Orderbook, config: %{max_orders: 1000}
```

### Connections

Define communication topology:

```elixir
connect :trader, :market                    # One-way: trader -> market
connect :trader, :market, bidirectional: true  # Two-way
connect :my_object, :metrics                # Connect to system objects
connect :my_object, :tick                   # System objects: :tick, :metrics, :gateway
```

### Measures

Define metrics computed at each step:

```elixir
measure :total_wealth, fn states ->
  states |> Map.values() |> Enum.map(&(&1["wealth"] || 0)) |> Enum.sum()
end

# Compute every N steps (for expensive metrics)
measure :gini_coefficient, [every: 5], fn states ->
  # expensive computation...
end
```

### Halt Conditions

Control when the simulation stops:

```elixir
# After N steps
halt after: 100

# When a predicate on current metrics is true
halt when: fn metrics -> metrics[:total_wealth] > 1_000_000 end

# When a metric has converged (varies less than threshold over window)
halt converged: [metric: :wealth, threshold: 100, window: 10]

# When a metric has plateaued (average change per step below threshold)
halt plateaued: [metric: :gini, threshold: 0.01, window: 5]

# Custom predicate with access to full metric history
halt when_history: fn {metrics, history} ->
  case history[:loss] do
    series when length(series) >= 10 ->
      recent = Enum.take(series, -10) |> Enum.map(&elem(&1, 1))
      Enum.max(recent) - Enum.min(recent) < 0.001
    _ -> false
  end
end
```

## CLI Commands

All commands use `mix sim <command>` format.

### Run a simulation

```bash
mix sim run path/to/simulation.sim [options]

Options:
  --steps N       Override maximum steps
  --parallel      Enable parallel mode for turn_based
  --quiet         Suppress progress output
  --metrics FILE  Export final metrics to JSON file
  --csv FILE      Export metrics as CSV files
  --timeout MS    Maximum runtime in milliseconds
```

### Check simulation status

```bash
mix sim status [name]        # Show running simulations
mix sim status my_sim        # Show specific simulation
```

### Stop a simulation

```bash
mix sim stop <name>          # Stop a running simulation
```

### View logs

```bash
mix sim logs <name> [options]
  --agent NAME    Filter by agent
  --follow        Stream new logs
  --tail N        Show last N lines
```

### View metrics

```bash
mix sim metrics <name> [options]
  --metric NAME   Show specific metric
  --export FILE   Export to JSON
```

### Query events

```bash
mix sim events <name> [options]
  --type TYPE     Filter by event type
  --agent NAME    Filter by agent
  --limit N       Limit results
```

### Validate simulation files

```bash
mix sim validate file1.sim file2.sim [options]

Options:
  --check-skills  Verify referenced skill files exist
  --verbose       Show detailed output
  --json          Output results as JSON
```

### Compare simulations

```bash
mix sim compare sim1.sim sim2.sim [options]

Options:
  --metric NAME   Metric to compare (can be repeated)
  --all-metrics   Compare all available metrics
  --steps N       Override max steps for all simulations
  --json          Output as JSON
  --csv           Output as CSV
```

### End-to-end test examples

```bash
mix sim.test                              # Validate + run all examples (3 steps each)
mix sim.test --validate-only              # Only validate syntax, don't run
mix sim.test --steps 5                    # Run with custom step count
mix sim.test --example counter            # Test a specific example
mix sim.test --timeout 120000             # Custom timeout per sim (ms)
mix sim.test --mock script.json           # Use canned responses instead of API
mix sim.test --logs-dir /tmp/sim-logs     # Custom logs directory

Options:
  --validate-only    Only validate, don't run
  --steps N          Steps per sim (default: 3)
  --example NAME     Test specific example only
  --timeout MS       Timeout per sim (default: 60000)
  --mock FILE        Mock script for canned responses
  --logs-dir DIR     Logs output directory (default: .test-logs/)
```

Logs are saved per simulation:
```
.test-logs/
├── counter.log
├── hello_world.log
├── ping_pong.log
└── summary.log
```

### Clean up simulation data

```bash
mix sim cleanup <name>       # Clean specific simulation
mix sim cleanup --all        # Clean all simulations
mix sim cleanup --completed  # Clean only completed simulations

Options:
  --force    Don't prompt for confirmation
```

## Examples

The `examples/` directory contains working simulations:

| Example | Mode | Description |
|---------|------|-------------|
| `hello_world` | turn_based | Simple 2-agent greeting simulation |
| `counter` | state_reports | 3 agents incrementing counters |
| `ping_pong` | turn_based | Ball bouncing with custom object handler |
| `two_teams` | turn_based | 8 agents across 2 teams with scoreboard |
| `halt_conditions` | state_reports | Custom halt predicates demo |
| `parallel_vs_sequential/parallel` | turn_based parallel | All agents act simultaneously |
| `parallel_vs_sequential/sequential` | turn_based sequential | Agents take turns in order |
| `time_interval` | time_interval | Steps advance every N seconds |
| `output_count` | output_count | Steps advance after N total LLM outputs |

Run an example:
```bash
source .env
mix sim run examples/hello_world/hello_world.sim
```

Validate all examples:
```bash
mix sim validate examples/**/*.sim
```

## Architecture

```
.sim file → Parser → %SimSpec{} → Compiler → swarm config → genswarms
                                     ↓
                              Injects Tick + Metrics objects
```

The compiler:
1. Expands roles into individual agents (`:trader` with count=5 → `:trader_1..5`)
2. Injects a `Tick` object for step coordination
3. Injects a `Metrics` object for state collection and metric computation
4. Auto-wires all user-defined objects to `:metrics` (so objects can send state_reports)
5. For counted roles (count > 1) with workspace config, appends agent name to workspace path for isolation
6. Generates topology with all necessary connections

## Message Protocol

### Tick → Agents
- `{"action": "new_step", "data": {"step": N}}`
- `{"action": "your_turn", "data": {"step": N}}` (turn_based mode)
- `{"action": "simulation_halted", "data": {"reason": "...", "step": N}}`

### Agents → Metrics
- `{"action": "state_report", "data": {"state": {...}}}`

### Coordinator → Tick (pipeline mode)
- `{"action": "advance_step"}` - Coordinator signals tick to advance to next step

### Metrics → Tick
- `{"action": "step_complete"}`
- `{"action": "halt", "data": {"reason": "..."}}`