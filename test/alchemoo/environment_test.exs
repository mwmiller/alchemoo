defmodule Alchemoo.EnvironmentTest do
  use ExUnit.Case
  alias Alchemoo.Builtins
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Value

  setup do
    # Ensure player #2 is in location #62
    {:ok, _obj} = DB.get_object(2)
    DB.move_object(2, 62)

    # Ensure #62 exists
    case DB.get_object(62) do
      {:ok, _} -> :ok
      # Create #62 if it doesn't exist
      _ -> DB.create_object(-1, 2)
    end

    :ok
  end

  test "me and here are available in eval" do
    # Simulate being player #2 in location #62
    Process.put(:task_context, %{
      player: 2,
      this: 2,
      caller: 2,
      perms: 2
    })

    runtime = Alchemoo.Runtime.new(DB.get_snapshot())
    env = %{runtime: runtime}

    # Eval "me"
    {:ok, {:list, [{:num, 1}, result_me]}, _env} =
      Builtins.call(:eval, [Value.str("return me;")], env)

    assert result_me == Value.obj(2)

    # Eval "here"
    {:ok, {:list, [{:num, 1}, result_here]}, _env} =
      Builtins.call(:eval, [Value.str("return here;")], env)

    assert result_here == Value.obj(62)

    # Eval "me.location"
    {:ok, {:list, [{:num, 1}, result_me_loc]}, _env} =
      Builtins.call(:eval, [Value.str("return me.location;")], env)

    assert result_me_loc == Value.obj(62)

    Process.delete(:task_context)
  end

  test "me and here in verb execution (should NOT be available by default)" do
    # We can test this by running a task directly
    code = "return {me, here};"
    # This should return E_VARNF
    assert {:error, {:err, :E_VARNF}} = Alchemoo.Task.run(code, %{}, player: 2, this: 2)
  end
end
