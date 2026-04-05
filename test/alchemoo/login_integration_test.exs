defmodule Alchemoo.LoginIntegrationTest do
  @moduledoc """
  Integration test for the full login flow.
  Verifies that a connecting player sees unread news items.
  """
  use ExUnit.Case, async: false

  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Runtime
  alias Alchemoo.Task
  alias Alchemoo.Value

  defmodule MockHandler do
    @moduledoc "Captures all output sent to the connection."
    use GenServer

    def start_link([]), do: GenServer.start_link(__MODULE__, [])

    def init(_), do: {:ok, %{output: []}}

    def get_output(pid), do: GenServer.call(pid, :get_output)
    def reset_output(pid), do: GenServer.call(pid, :reset_output)

    def send_output(pid, text) when is_binary(text),
      do: GenServer.cast(pid, {:output, text})

    def handle_call(:register_self, _from, state) do
      Registry.register(Alchemoo.PlayerRegistry, 2, %{pid: self()})
      {:reply, :ok, state}
    end

    def handle_call(:get_output, _from, state),
      do: {:reply, state.output, state}

    def handle_call(:reset_output, _from, state),
      do: {:reply, :ok, %{state | output: []}}

    def handle_cast({:output, text}, state),
      do: {:noreply, %{state | output: [text | state.output]}}
  end

  defp full_output(handler_pid), do: MockHandler.get_output(handler_pid) |> Enum.reverse() |> Enum.join("")
  defp reset_output(handler_pid), do: MockHandler.reset_output(handler_pid)

  describe "news display on login" do
    setup do
      {:ok, handler_pid} = MockHandler.start_link([])

      # Register the mock handler in the PlayerRegistry for player #2
      # Must be done from the handler's own process
      GenServer.call(handler_pid, :register_self)

      on_exit(fn ->
        Process.delete(:task_context)
        Process.delete(:ticks_remaining)
      end)

      %{handler_pid: handler_pid}
    end

    test "$news:check notifies player about unread news", %{handler_pid: handler_pid} do
      # Clear player #2's news tracking so news appears unread
      DB.set_property(2, "current_message", Value.list([]))
      reset_output(handler_pid)

      # Call $news:check() with proper task context
      result = call_verb(2, 61, "check", [], handler_pid)

      output = full_output(handler_pid)

      # The verb should succeed
      assert match?({:ok, _}, result), "news:check returned #{inspect(result)}"

      # Player should be told about new news
      assert String.contains?(output, "new news") or String.contains?(output, "News"),
             """
             $news:check should notify player about unread news.

             Output:
             #{output}
             """
    end

    test "full confunc chain fires news check on login", %{handler_pid: handler_pid} do
      player_id = 2

      # Reset mail/news tracking
      DB.set_property(player_id, "current_message", Value.list([]))
      reset_output(handler_pid)

      # Run the confunc chain as user_connected does
      result = run_confunc_chain(player_id, handler_pid)

      output = full_output(handler_pid)

      assert match?({:ok, _}, result),
             "confunc chain failed: #{inspect(result)}"

      # Should have output - news notification or room description
      refute output == "",
             """
             confunc should produce output.

             Output was empty.
             """
    end

    test "confunc verb finds and calls $news:check", %{handler_pid: handler_pid} do
      # Clear current_message so news appears unread
      DB.set_property(2, "current_message", Value.list([]))
      reset_output(handler_pid)

      # Call confunc on the player (this calls #6:confunc which calls $news:check)
      result = call_verb(2, 2, "confunc", [], handler_pid)

      output = full_output(handler_pid)

      # confunc should succeed
      assert match?({:ok, _}, result),
             "confunc returned #{inspect(result)}"

      # Should mention news
      assert String.contains?(output, "news") or String.contains?(output, "News"),
             """
             confunc should trigger news check.

             Output:
             #{output}
             """
    end
  end

  ## Helpers

  defp call_verb(player_id, obj_id, verb_name, args, handler_pid) do
    runtime = Runtime.new(DB.get_snapshot())

    env = %{
      :runtime => runtime,
      "player" => Value.obj(player_id),
      "this" => Value.obj(obj_id),
      "caller" => Value.obj(0),
      "verb" => Value.str(verb_name),
      "argstr" => Value.str(""),
      "args" => Value.list(args)
    }

    task_opts = [
      player: player_id,
      this: obj_id,
      caller: 0,
      perms: player_id,
      caller_perms: player_id,
      handler_pid: handler_pid,
      verb_name: verb_name,
      args: args
    ]

    case find_verb(obj_id, verb_name) do
      {:ok, verb} ->
        code = Enum.join(verb.code, "\n")
        Task.run(code, env, task_opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_confunc_chain(player_id, handler_pid) do
    # Simulate what #0:user_connected does:
    #   user.location:confunc(user)
    #   user:confunc()

    # Get player's location (Limbo #15 for wizard)
    {:ok, player_obj} = DB.get_object(player_id)
    location_id = player_obj.location

    # Call location:confunc(player) - Limbo confunc
    _loc_result =
      call_verb_with_args(player_id, location_id, "confunc", [player_id], handler_pid)

    # Call player:confunc()
    call_verb(player_id, player_id, "confunc", [], handler_pid)
  end

  defp call_verb_with_args(player_id, obj_id, verb_name, args, handler_pid) do
    runtime = Runtime.new(DB.get_snapshot())

    env = %{
      :runtime => runtime,
      "player" => Value.obj(player_id),
      "this" => Value.obj(obj_id),
      "caller" => Value.obj(0),
      "verb" => Value.str(verb_name),
      "argstr" => Value.str(""),
      "args" => Value.list(args)
    }

    task_opts = [
      player: player_id,
      this: obj_id,
      caller: 0,
      perms: player_id,
      caller_perms: player_id,
      handler_pid: handler_pid,
      verb_name: verb_name,
      args: args
    ]

    case find_verb(obj_id, verb_name) do
      {:ok, verb} ->
        code = Enum.join(verb.code, "\n")
        Task.run(code, env, task_opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_verb(obj_id, verb_name) do
    db = DB.get_snapshot()

    case Map.get(db.objects, obj_id) do
      nil -> {:error, :E_INVIND}
      obj -> search_verb_chain(db, obj, verb_name)
    end
  end

  defp search_verb_chain(db, obj, verb_name) do
    matching =
      Enum.find(obj.verbs, fn v ->
        v.name
        |> String.split(" ")
        |> Enum.any?(fn pat -> String.downcase(pat) == String.downcase(verb_name) end)
      end)

    case matching do
      nil when obj.parent >= 0 ->
        case Map.get(db.objects, obj.parent) do
          nil -> {:error, :E_VERBNF}
          parent -> search_verb_chain(db, parent, verb_name)
        end

      nil ->
        {:error, :E_VERBNF}

      verb ->
        {:ok, verb}
    end
  end
end
