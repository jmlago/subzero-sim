defmodule SimValidatorCLI do
  @moduledoc """
  Standalone validation server for SubzeroSim .sim files.

  Reads sim file paths from stdin (one per line) and prints validation results.
  The BEAM VM stays warm between validations — no cold-start penalty.

  ## Usage

  As a long-running stdin server:

      echo "/path/to/sim.sim" | mix run -e "SimValidatorCLI.run()"

  Or for multiple files:

      find examples -name "*.sim" | mix run -e "SimValidatorCLI.run()"

  ## Output

  For each input path, prints one line:

      OK /path/to/sim.sim
      FAIL /path/to/sim.sim: error message

  ## As an escript (for bwrap agents)

  Build:
      mix escript.build --name sim_validator

  Run inside bwrap:
      echo "/workspace/sim.sim" | /project/sim_validator
  """

  def run do
    Application.ensure_all_started(:subzero_sim)

    IO.stream(:stdio, :line)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.each(&validate_one/1)
  end

  def main(args) do
    Application.ensure_all_started(:subzero_sim)

    case args do
      [] ->
        # Read from stdin
        run()

      paths ->
        # Validate each path argument
        Enum.each(paths, &validate_one/1)
    end
  end

  defp validate_one(path) do
    case SubzeroSim.Loader.load(path) do
      {:ok, spec} ->
        case SubzeroSim.Validator.validate(spec) do
          :ok ->
            IO.puts("OK #{path}")

          {:error, errors} when is_list(errors) ->
            IO.puts("FAIL #{path}: #{Enum.join(errors, "; ")}")

          {:error, error} ->
            IO.puts("FAIL #{path}: #{inspect(error)}")
        end

      {:error, reason} ->
        IO.puts("FAIL #{path}: #{format_error(reason)}")
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
