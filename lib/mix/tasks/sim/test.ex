defmodule Mix.Tasks.Sim.Test do
  @moduledoc """
  Runs end-to-end tests on all example simulations.

  ## Usage

      mix sim.test                    # Validate + run all examples (3 steps each)
      mix sim.test --validate-only    # Only validate syntax, don't run
      mix sim.test --steps 5          # Run with custom step count
      mix sim.test --example counter  # Test a specific example
      mix sim.test --timeout 30000    # Custom timeout per sim (ms)
      mix sim.test --logs-dir /tmp/sim-test-logs  # Save full logs

  ## What it does

  1. Discovers all .sim files in examples/
  2. Validates each one (syntax + structure)
  3. Runs each with --steps 3 (or custom)
  4. Captures full logs per simulation to logs directory
  5. Reports pass/fail for each

  ## Logs

  When --logs-dir is specified (default: .test-logs/), full output from each
  simulation run is saved to a file named after the example:

      .test-logs/
      ├── counter.log
      ├── hello_world.log
      ├── ping_pong.log
      └── summary.log

  Review logs with: cat .test-logs/counter.log

  Exit code is 0 if all pass, 1 if any fail.
  """

  use Mix.Task

  alias SubzeroSim.{Loader, Validator}

  @shortdoc "Run e2e tests on example simulations"

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          validate_only: :boolean,
          steps: :integer,
          example: :string,
          timeout: :integer,
          quiet: :boolean,
          logs_dir: :string,
          mock: :string
        ]
      )

    Application.ensure_all_started(:subzero_sim)

    # Mock mode: set env var so subzeroclaw uses canned responses instead of API
    if opts[:mock] do
      mock_path = Path.expand(opts[:mock])
      System.put_env("SUBZEROCLAW_MOCK_SCRIPT", mock_path)
      Mix.shell().info("Mock mode: #{mock_path}")
    end

    examples_dir = Path.join(File.cwd!(), "examples")
    steps = opts[:steps] || 3
    timeout = opts[:timeout] || 60_000
    validate_only = opts[:validate_only] || false
    quiet = opts[:quiet] || false
    logs_dir = Path.expand(opts[:logs_dir] || ".test-logs")

    unless validate_only do
      File.mkdir_p!(logs_dir)
      Mix.shell().info("Logs directory: #{logs_dir}")
    end

    # Discover sim files
    sim_files =
      examples_dir
      |> Path.join("**/*.sim")
      |> Path.wildcard()
      |> Enum.sort()
      |> maybe_filter_example(opts[:example])

    if sim_files == [] do
      Mix.shell().error("No .sim files found in #{examples_dir}")
      System.halt(1)
    end

    Mix.shell().info("\n=== SubzeroSim E2E Tests ===")
    Mix.shell().info("Found #{length(sim_files)} simulations\n")

    results =
      Enum.map(sim_files, fn sim_file ->
        relative = Path.relative_to(sim_file, File.cwd!())
        test_sim(relative, sim_file, steps, timeout, validate_only, quiet, logs_dir)
      end)

    # Summary
    passed = Enum.count(results, fn {s, _} -> s == :pass end)
    failed = Enum.count(results, fn {s, _} -> s == :fail end)
    skipped = Enum.count(results, fn {s, _} -> s == :skip end)

    summary = "#{passed} passed, #{failed} failed, #{skipped} skipped"

    Mix.shell().info("\n=== Results ===")
    Mix.shell().info(summary)

    unless validate_only do
      # Write summary log
      summary_lines = Enum.map(results, fn {status, name} ->
        icon = case status do
          :pass -> "✓"
          :fail -> "✗"
          :skip -> "⊘"
        end
        "#{icon} #{name}"
      end)

      summary_path = Path.join(logs_dir, "summary.log")
      File.write!(summary_path, Enum.join(["=== #{summary} ===\n" | summary_lines], "\n"))
      Mix.shell().info("Summary written to: #{summary_path}")
    end

    if failed > 0, do: System.halt(1)
  end

  defp test_sim(relative, sim_file, steps, timeout, validate_only, quiet, logs_dir) do
    # Phase 1: Validate
    case Loader.load(sim_file) do
      {:ok, spec} ->
        case Validator.validate(spec) do
          :ok ->
            if validate_only do
              unless quiet, do: Mix.shell().info("  \e[32m✓\e[0m #{relative} (valid)")
              {:pass, relative}
            else
              # Phase 2: Run with log capture
              run_sim(relative, spec, steps, timeout, quiet, logs_dir)
            end

          {:error, errors} ->
            Mix.shell().error("  \e[31m✗\e[0m #{relative} (validation: #{inspect(errors)})")
            {:fail, relative}
        end

      {:error, reason} ->
        Mix.shell().error("  \e[31m✗\e[0m #{relative} (load: #{inspect(reason)})")
        {:fail, relative}
    end
  end

  defp run_sim(relative, spec, steps, timeout, quiet, logs_dir) do
    # Log file named after the example
    log_name = spec.name |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
    log_path = Path.join(logs_dir, "#{log_name}.log")

    spec = %{spec | steps: steps}

    # Capture all log output for this sim run
    _log_lines = []

    task =
      Task.async(fn ->
        try do
          case SubzeroSim.Runner.run_and_collect(spec, steps: steps, timeout: timeout) do
            {:ok, info} -> {:ok, info}
            {:error, reason} -> {:error, reason}
          end
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    result = Task.yield(task, timeout + 5_000) || Task.shutdown(task)

    # Write log with run details
    log_content = [
      "=== #{relative} ===",
      "Steps: #{steps}, Timeout: #{timeout}ms",
      "Sim name: #{spec.name}",
      "Agents: #{inspect(Enum.map(spec.roles, & &1.name))}",
      "Objects: #{inspect(Enum.map(spec.objects, & &1.name))}",
      "",
      case result do
        {:ok, {:ok, info}} ->
          metrics = Map.get(info, :metrics, %{})
          [
            "Status: #{Map.get(info, :status, :unknown)}",
            "Final step: #{Map.get(info, :final_step, "?")}",
            "Halt reason: #{Map.get(info, :halt_reason, "none")}",
            "Metrics: #{inspect(metrics)}"
          ]
        {:ok, {:error, reason}} ->
          ["ERROR: #{inspect(reason)}"]
        nil ->
          ["TIMEOUT after #{timeout}ms"]
      end
    ]
    |> List.flatten()
    |> Enum.join("\n")

    File.write!(log_path, log_content)

    case result do
      {:ok, {:ok, info}} ->
        status = Map.get(info, :status, :unknown)
        final_step = Map.get(info, :final_step, "?")
        unless quiet do
          Mix.shell().info("  \e[32m✓\e[0m #{relative} (#{final_step} steps, #{status}) → #{log_path}")
        end
        {:pass, relative}

      {:ok, {:error, reason}} ->
        Mix.shell().error("  \e[31m✗\e[0m #{relative} (#{inspect(reason)}) → #{log_path}")
        {:fail, relative}

      nil ->
        Mix.shell().error("  \e[31m✗\e[0m #{relative} (timeout) → #{log_path}")
        {:fail, relative}
    end
  end

  defp maybe_filter_example(files, nil), do: files

  defp maybe_filter_example(files, name) do
    Enum.filter(files, fn path ->
      String.contains?(path, "/#{name}/")
    end)
  end
end
