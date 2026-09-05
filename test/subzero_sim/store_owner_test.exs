defmodule SubzeroSim.StoreOwnerTest do
  use ExUnit.Case, async: false

  test "short-lived callers cannot close the application's result table on exit" do
    assert Process.whereis(SubzeroSim.Store.Owner)

    for n <- 1..30 do
      task = Task.async(fn -> SubzeroSim.Store.ResultStore.put("owner-test", n) end)
      assert :ok = Task.await(task)
      assert SubzeroSim.Store.ResultStore.get("owner-test") == n
    end

    assert :ok = SubzeroSim.Store.ResultStore.cleanup("owner-test")
  end
end
