defmodule SimCLI do
  @moduledoc """
  Combined CLI for SubzeroSim — validates and runs simulations.

  ## Usage

      sim_cli validate /path/to/sim.sim       # Validate (fast, ~40ms)
      sim_cli run /path/to/sim.sim            # Run (starts agents)
      sim_cli run /path/to/sim.sim --steps 5  # Run with custom steps

  ## Build

      mix escript.build
  """

  def main(args) do
    case args do
      ["validate" | rest] -> SimValidatorCLI.main(rest)
      ["run" | rest] -> SimRunnerCLI.main(rest)
      _ ->
        IO.puts(:stderr, """
        sim_cli — SubzeroSim command line tool

        Usage:
          sim_cli validate <sim_file> [more...]    Validate sim files
          sim_cli run <sim_file> [--steps N]        Run a simulation
        """)
        System.halt(1)
    end
  end
end
