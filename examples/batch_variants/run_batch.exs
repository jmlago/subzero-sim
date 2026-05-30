# Run with: mix run examples/batch_variants/run_batch.exs
#
# This script demonstrates using Batch.run_variants to run multiple
# variants of a simulation with different worker counts.

# Load the base simulation
{:ok, base} = SubzeroSim.Loader.load("examples/batch_variants/base.sim")

IO.puts("Loaded base simulation: #{base.name}")
IO.puts("Base worker count: #{Enum.find(base.roles, &(&1.name == :worker)).count}")
IO.puts("")

# Create variant functions that modify the worker count
variants =
  for i <- 1..5 do
    fn spec ->
      spec
      |> SubzeroSim.Variant.set_agent_count(:worker, i)
      |> SubzeroSim.Variant.set_name("batch_variant_#{i}_workers")
    end
  end

IO.puts("Running #{length(variants)} variants with max_concurrent: 2")
IO.puts("")

# Run all variants with a concurrency limit
results =
  SubzeroSim.Batch.run_variants(base, variants,
    max_concurrent: 2,
    on_complete: fn spec, result ->
      case result do
        {:ok, info} ->
          IO.puts("Completed: #{spec.name} - final step: #{info.final_step}, output: #{inspect(info.metrics[:output])}")

        {:error, reason} ->
          IO.puts("Failed: #{spec.name} - #{inspect(reason)}")
      end
    end
  )

IO.puts("")
IO.puts("=== Summary ===")
IO.puts("Completed: #{length(results.completed)}")
IO.puts("Failed: #{length(results.failed)}")

# Print detailed results
if length(results.completed) > 0 do
  IO.puts("")
  IO.puts("=== Results ===")

  Enum.each(results.completed, fn {spec, {:ok, info}} ->
    worker_count =
      case Enum.find(spec.roles, &(&1.name == :worker)) do
        nil -> "?"
        role -> role.count
      end

    output = Map.get(info.metrics, :output, 0)
    IO.puts("#{spec.name}: #{worker_count} workers -> output: #{output}")
  end)
end
