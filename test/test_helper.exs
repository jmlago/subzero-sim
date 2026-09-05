ExUnit.start()

# Do not start Genswarms or load the developer's .env for deterministic tests.
# The Mix test alias supplies --no-start, including for focused invocations.
test_dir = Path.join(System.tmp_dir!(), "subzero-sim-test-#{System.unique_integer([:positive])}")
File.mkdir_p!(test_dir)
Application.put_env(:subzero_sim, :data_dir, test_dir)

ExUnit.after_suite(fn _ ->
  for table <- [
        :subzero_sim_runtime,
        :subzero_sim_states,
        :subzero_sim_metrics,
        :subzero_sim_results,
        :subzero_sim_checkpoints
      ] do
    if :dets.info(table) != :undefined, do: :dets.close(table)
  end

  File.rm_rf!(test_dir)
end)
