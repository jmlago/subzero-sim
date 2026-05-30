defmodule Mix.Tasks.Sim.Validate do
  @moduledoc """
  Validates one or more .sim files.

  Checks that:
  - The file exists and has valid syntax
  - The DSL produces a valid SimSpec
  - All validation rules pass
  - The spec compiles to a valid swarm config
  - Referenced skill files exist (if --check-skills is passed)

  ## Usage

      mix sim.validate path/to/simulation.sim [more files...] [options]

  ## Options

    * `--check-skills` - Also verify that referenced skill files exist
    * `--verbose` - Show detailed validation output
    * `--json` - Output results as JSON

  ## Examples

      # Validate a single file
      mix sim.validate examples/market.sim

      # Validate multiple files
      mix sim.validate examples/*.sim

      # Validate with skill file checks
      mix sim.validate examples/market.sim --check-skills
  """

  use Mix.Task

  alias SubzeroSim.{Loader, Validator, Compiler}

  @shortdoc "Validates .sim files"

  @impl true
  def run(args) do
    # Start the application (needed for Jason, etc.)
    Mix.Task.run("app.start")

    {opts, files, _invalid} =
      OptionParser.parse(args,
        strict: [
          check_skills: :boolean,
          verbose: :boolean,
          json: :boolean
        ]
      )

    if Enum.empty?(files) do
      Mix.shell().error("Usage: mix sim.validate <file.sim> [more files...] [options]")
      exit({:shutdown, 1})
    end

    results = Enum.map(files, &validate_file(&1, opts))

    if opts[:json] do
      output_json(results)
    else
      output_text(results, opts)
    end

    # Exit with error if any file failed
    if Enum.any?(results, fn r -> not r.valid end) do
      exit({:shutdown, 1})
    end
  end

  defp validate_file(path, opts) do
    result = %{
      file: path,
      valid: true,
      errors: [],
      warnings: []
    }

    result
    |> check_file_exists(path)
    |> check_loads(path)
    |> check_validates()
    |> check_compiles()
    |> check_skills(opts[:check_skills])
  end

  defp check_file_exists(result, path) do
    if result.valid do
      if File.exists?(path) do
        result
      else
        %{result | valid: false, errors: ["File not found: #{path}" | result.errors]}
      end
    else
      result
    end
  end

  defp check_loads(result, path) do
    if result.valid do
      case Loader.load(path) do
        {:ok, spec} ->
          Map.put(result, :spec, spec)

        {:error, {:compile_error, msg}} ->
          %{result | valid: false, errors: ["Compile error: #{msg}" | result.errors]}

        {:error, {:syntax_error, msg}} ->
          %{result | valid: false, errors: ["Syntax error: #{msg}" | result.errors]}

        {:error, reason} ->
          %{result | valid: false, errors: ["Load error: #{inspect(reason)}" | result.errors]}
      end
    else
      result
    end
  end

  defp check_validates(result) do
    if result.valid and Map.has_key?(result, :spec) do
      case Validator.validate(result.spec) do
        :ok ->
          result

        {:error, errors} ->
          %{result | valid: false, errors: errors ++ result.errors}
      end
    else
      result
    end
  end

  defp check_compiles(result) do
    if result.valid and Map.has_key?(result, :spec) do
      # Compiler.compile/1 currently always succeeds, but we wrap in try for safety
      try do
        {:ok, _config} = Compiler.compile(result.spec)
        result
      rescue
        e -> %{result | valid: false, errors: ["Compile error: #{Exception.message(e)}" | result.errors]}
      end
    else
      result
    end
  end

  defp check_skills(result, check_skills?) do
    if result.valid and check_skills? == true and Map.has_key?(result, :spec) do
      missing_skills =
        result.spec.roles
        |> Enum.filter(& &1.skill)
        |> Enum.map(& &1.skill)
        |> Enum.reject(&File.exists?/1)

      if Enum.empty?(missing_skills) do
        result
      else
        warnings =
          Enum.map(missing_skills, fn skill ->
            "Skill file not found: #{skill}"
          end)

        %{result | warnings: warnings ++ result.warnings}
      end
    else
      result
    end
  end

  defp output_text(results, opts) do
    passed = Enum.count(results, & &1.valid)
    failed = length(results) - passed

    Enum.each(results, fn result ->
      if result.valid do
        if opts[:verbose] do
          Mix.shell().info("#{IO.ANSI.green()}[PASS]#{IO.ANSI.reset()} #{result.file}")

          if Map.has_key?(result, :spec) do
            spec = result.spec
            Mix.shell().info("       Name: #{spec.name}")
            Mix.shell().info("       Mode: #{spec.tick_config.mode}")
            Mix.shell().info("       Roles: #{length(spec.roles)}")
            Mix.shell().info("       Agents: #{length(SubzeroSim.Spec.SimSpec.agent_names(spec))}")
          end
        else
          Mix.shell().info("#{IO.ANSI.green()}[PASS]#{IO.ANSI.reset()} #{result.file}")
        end

        Enum.each(result.warnings, fn warning ->
          Mix.shell().info("       #{IO.ANSI.yellow()}Warning: #{warning}#{IO.ANSI.reset()}")
        end)
      else
        Mix.shell().error("#{IO.ANSI.red()}[FAIL]#{IO.ANSI.reset()} #{result.file}")

        Enum.each(result.errors, fn error ->
          Mix.shell().error("       #{error}")
        end)
      end
    end)

    Mix.shell().info("")

    if failed > 0 do
      Mix.shell().error("#{passed} passed, #{failed} failed")
    else
      Mix.shell().info("#{IO.ANSI.green()}All #{passed} files valid#{IO.ANSI.reset()}")
    end
  end

  defp output_json(results) do
    output =
      Enum.map(results, fn result ->
        %{
          file: result.file,
          valid: result.valid,
          errors: result.errors,
          warnings: result.warnings
        }
      end)

    IO.puts(Jason.encode!(output, pretty: true))
  end
end
