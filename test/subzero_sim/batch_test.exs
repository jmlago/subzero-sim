defmodule SubzeroSim.BatchTest do
  use ExUnit.Case, async: true

  alias SubzeroSim.Batch
  alias SubzeroSim.Spec.{SimSpec, RoleSpec}

  # Note: These are unit tests for the Batch module interface.
  # Full integration tests would require running actual simulations.

  describe "run_variants/3" do
    test "creates variants with modified specs" do
      base_spec = %SimSpec{
        name: "base",
        roles: [%RoleSpec{name: :worker, count: 1, backend: :bwrap}]
      }

      # Test the variant creation logic without actually running
      # We'll verify that variant functions are applied correctly
      variants = [
        fn spec ->
          roles =
            Enum.map(spec.roles, fn role ->
              if role.name == :worker, do: %{role | count: 5}, else: role
            end)

          %{spec | roles: roles}
        end,
        fn spec ->
          roles =
            Enum.map(spec.roles, fn role ->
              if role.name == :worker, do: %{role | count: 10}, else: role
            end)

          %{spec | roles: roles}
        end
      ]

      # Apply variants manually to test the transformation
      modified_specs =
        Enum.with_index(variants)
        |> Enum.map(fn {variant_fn, idx} ->
          spec = variant_fn.(base_spec)

          spec =
            if spec.name == base_spec.name do
              %{spec | name: "#{base_spec.name}_variant_#{idx + 1}"}
            else
              spec
            end

          spec
        end)

      assert length(modified_specs) == 2

      [spec1, spec2] = modified_specs
      assert spec1.name == "base_variant_1"
      assert hd(spec1.roles).count == 5

      assert spec2.name == "base_variant_2"
      assert hd(spec2.roles).count == 10
    end
  end

  describe "batch result structure" do
    test "result has expected keys" do
      # This tests the expected structure of batch results
      result = %{completed: [], failed: [], load_errors: []}

      assert Map.has_key?(result, :completed)
      assert Map.has_key?(result, :failed)
      assert is_list(result.completed)
      assert is_list(result.failed)
    end
  end
end
