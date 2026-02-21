defmodule Alchemoo.Command.ExecutorTest do
  use ExUnit.Case, async: false

  alias Alchemoo.Command.Executor

  setup do
    # Use wizard player (#2) from loaded database
    player_id = 2
    handler_pid = self()

    {:ok, player_id: player_id, handler_pid: handler_pid}
  end

  describe "execute/3" do
    test "executes command", %{player_id: player_id, handler_pid: handler_pid} do
      # Just verify it doesn't crash
      result = Executor.execute("look", player_id, handler_pid)
      assert is_tuple(result)
    end

    test "returns error for empty command", %{player_id: player_id, handler_pid: handler_pid} do
      assert {:error, :empty_command} = Executor.execute("", player_id, handler_pid)
    end

    test "handles verb with arguments", %{player_id: player_id, handler_pid: handler_pid} do
      result = Executor.execute("look me", player_id, handler_pid)
      assert is_tuple(result)
    end
  end
end
