# Two Teams Example

## Overview

Demonstrates **multi-role simulations** with two competing teams, showing how different agent types can interact through shared objects.

## What It Tests

- **Multiple agent roles** - two distinct teams with different behaviors
- **Asymmetric team sizes** - team_a has 5 agents, team_b has 3
- **Shared object interaction** - both teams write to a scoreboard
- **Per-team metrics** - aggregate scores computed for each team
- **Role-based filtering** in metric functions

## How It Works

```
Agents:
  team_a_1, team_a_2, team_a_3, team_a_4, team_a_5  (5 agents)
  team_b_1, team_b_2, team_b_3                       (3 agents)

Each step:
  1. Each agent on their turn contributes points
  2. Points sent to shared scoreboard object
  3. Metrics computed: team_a_score, team_b_score
```

## Why This Example Matters

Multi-team simulations are essential for:

- **Competition modeling** - teams competing for resources
- **Coalition dynamics** - how groups coordinate internally
- **A/B testing** - compare different agent strategies
- **Market simulations** - multiple competing firms

## Key Files

- `two_teams.sim` - Simulation definition
- `skills/team_a.md` - Team A agent behavior
- `skills/team_b.md` - Team B agent behavior
- `objects/scoreboard.ex` - Shared scoreboard object

## Running

```bash
mix sim.run examples/two_teams/two_teams.sim
```

## Expected Output

```
Simulation completed!
  Final step: 10
  Status: completed

Final metrics:
  team_a_score: X
  team_b_score: Y
```

## Configuration

```elixir
# Define two teams with different sizes
agent :team_a, count: 5 do
  skill "skills/team_a.md"
end

agent :team_b, count: 3 do
  skill "skills/team_b.md"
end

# Both teams connect to shared scoreboard
connect :team_a, :scoreboard
connect :team_b, :scoreboard
```

## Metrics

Team-specific metrics using name filtering:

```elixir
measure :team_a_score, fn states ->
  states
  |> Enum.filter(fn {name, _} ->
       String.starts_with?(to_string(name), "team_a")
     end)
  |> Enum.map(fn {_, s} -> Map.get(s, "points_contributed", 0) end)
  |> Enum.sum()
end
```

## Use Cases

### Market Competition
```elixir
agent :firm_a, count: 3, skill: "aggressive_strategy.md"
agent :firm_b, count: 3, skill: "conservative_strategy.md"
```

### Sports Simulation
```elixir
agent :home_team, count: 11, skill: "home_tactics.md"
agent :away_team, count: 11, skill: "away_tactics.md"
```

### Political Simulation
```elixir
agent :party_a, count: 50, skill: "liberal_platform.md"
agent :party_b, count: 45, skill: "conservative_platform.md"
agent :independent, count: 5, skill: "moderate_platform.md"
```

## Design Notes

### Asymmetric Teams
Team sizes don't need to match. This allows modeling:
- Resource imbalances
- Underdog scenarios
- Majority/minority dynamics

### Shared Objects
The scoreboard object receives messages from both teams, allowing:
- Central state tracking
- Cross-team visibility
- Referee/arbiter patterns
