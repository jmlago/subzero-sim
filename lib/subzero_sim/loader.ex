defmodule SubzeroSim.Loader do
  @moduledoc """
  Loads simulation specifications from .sim files.

  .sim files are Elixir scripts that use the SubzeroSim.DSL to define simulations.
  """

  alias SubzeroSim.Spec.SimSpec

  @doc """
  Loads a simulation specification from a file.

  The file should be an Elixir script (.sim or .exs) that uses the SubzeroSim.DSL
  and evaluates to a `%SimSpec{}` struct.

  ## Example

      # my_simulation.sim
      use SubzeroSim.DSL

      simulation "my_sim" do
        agent :worker, count: 3
        steps 100
      end

  """
  @spec load(String.t()) :: {:ok, SimSpec.t()} | {:error, term()}
  def load(path) do
    path = Path.expand(path)

    if File.exists?(path) do
      do_load(path)
    else
      {:error, {:file_not_found, path}}
    end
  end

  @doc """
  Loads a simulation specification from a string.
  """
  @spec load_string(String.t()) :: {:ok, SimSpec.t()} | {:error, term()}
  def load_string(code) do
    do_eval(code, "nofile")
  end

  defp do_load(path) do
    code = File.read!(path)
    do_eval(code, path)
  end

  defp do_eval(code, path) do
    try do
      {result, _binding} = Code.eval_string(code, [], file: path)

      case result do
        %SimSpec{} = spec ->
          # Set source_dir from file path
          source_dir = if path != "nofile", do: Path.dirname(path), else: nil
          {:ok, %{spec | source_dir: source_dir}}

        other ->
          {:error, {:invalid_result, "Expected %SimSpec{}, got: #{inspect(other)}"}}
      end
    rescue
      e in CompileError ->
        {:error, {:compile_error, Exception.message(e)}}

      e in SyntaxError ->
        {:error, {:syntax_error, Exception.message(e)}}

      e ->
        {:error, {:evaluation_error, Exception.message(e)}}
    end
  end
end
