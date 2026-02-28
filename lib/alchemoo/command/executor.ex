defmodule Alchemoo.Command.Executor do
  @moduledoc """
  Executes MOO commands by finding and running verbs.
  """

  alias Alchemoo.Command.Parser
  alias Alchemoo.Connection.Handler
  alias Alchemoo.Database.Resolver
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Runtime
  alias Alchemoo.TaskSupervisor
  alias Alchemoo.Value

  @doc """
  Execute a command for a player.

  Returns:
    {:ok, task_pid} - Task spawned successfully
    {:error, reason} - Failed to execute
  """
  def execute(command, player_id, handler_pid) do
    case execute_via_core_do_command(command, player_id, handler_pid) do
      :fallback ->
        execute_with_local_parser(command, player_id, handler_pid)

      result ->
        result
    end
  end

  defp execute_via_core_do_command(command, player_id, handler_pid) do
    case DB.find_verb(0, "do_command") do
      {:ok, 0, verb} ->
        words = String.split(command, ~r/\s+/, trim: true)
        runtime = Runtime.new(DB.get_snapshot())

        env = %{
          :runtime => runtime,
          "player" => Value.obj(player_id),
          "this" => Value.obj(0),
          "caller" => Value.obj(-1),
          "verb" => Value.str("do_command"),
          "argstr" => Value.str(command),
          "args" => Value.list(Enum.map(words, &Value.str/1))
        }

        task_opts = [
          player: player_id,
          this: 0,
          caller: -1,
          perms: 2,
          caller_perms: 2,
          args: Enum.map(words, &Value.str/1),
          handler_pid: handler_pid,
          verb_name: "do_command"
        ]

        code = Enum.join(verb.code, "\n")

        case TaskSupervisor.spawn_task(code, env, task_opts) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, reason} ->
            send_error(handler_pid, "Error executing command: #{inspect(reason)}")
            {:error, reason}
        end

      _ ->
        :fallback
    end
  end

  defp execute_with_local_parser(command, player_id, handler_pid) do
    db = DB.get_snapshot()

    case Parser.parse(command) do
      {:ok, parsed} ->
        execute_parsed(parsed, player_id, db, handler_pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_parsed(parsed, player_id, db, handler_pid) do
    # Resolve dobj and iobj names to IDs
    parsed = resolve_object_ids(parsed, player_id, db)

    # Find verb target (the receiver)
    case Parser.find_verb_target(parsed, player_id, db) do
      {:ok, receiver_id, verb_name} ->
        # Look up verb (find where it's defined)
        case Resolver.find_verb(db, receiver_id, verb_name) do
          {:ok, _definer_id, verb} ->
            # Execute verb on the receiver_id
            execute_verb(verb, receiver_id, player_id, parsed, handler_pid)

          {:error, :E_VERBNF} ->
            # Verb not found, send error
            send_error(handler_pid, "I don't understand that.")
            {:error, :verb_not_found}

          error ->
            error
        end

      error ->
        # Verb not found in search order
        send_error(handler_pid, "I don't understand that.")
        error
    end
  end

  defp resolve_object_ids(parsed, player_id, db) do
    dobj_id = resolve_object_id(parsed.dobj, player_id, db)
    iobj_id = resolve_object_id(parsed.iobj, player_id, db)

    parsed
    |> Map.put(:dobj_id, dobj_id)
    |> Map.put(:iobj_id, iobj_id)
  end

  defp resolve_object_id(nil, _player_id, _db), do: -1
  defp resolve_object_id("", _player_id, _db), do: -1

  defp resolve_object_id(name, player_id, db) do
    search_name = String.downcase(name)

    # Try me/here/IDs
    case resolve_special_id(search_name, player_id, db) do
      {:ok, id} ->
        id

      :not_special ->
        # Search contents
        search_vicinity(search_name, player_id, db)
    end
  end

  defp resolve_special_id("me", player_id, _db), do: {:ok, player_id}

  defp resolve_special_id("here", player_id, db) do
    case Map.fetch(db.objects, player_id) do
      {:ok, obj} -> {:ok, obj.location}
      _ -> {:ok, -1}
    end
  end

  defp resolve_special_id("#" <> id_str, _player_id, _db) do
    case Integer.parse(id_str) do
      {id, ""} -> {:ok, id}
      _ -> :not_special
    end
  end

  defp resolve_special_id(_, _, _), do: :not_special

  defp search_vicinity(name, player_id, db) do
    with {:ok, player} <- Map.fetch(db.objects, player_id),
         {:ok, here} <- Map.fetch(db.objects, player.location) do
      # Search player contents, then room contents
      candidates = player.contents ++ here.contents
      Enum.find(candidates, -1, &object_matches_name?(&1, name, db))
    else
      _ -> -1
    end
  end

  defp object_matches_name?(id, name, db) do
    case Map.fetch(db.objects, id) do
      {:ok, obj} -> String.downcase(obj.name) == name
      _ -> false
    end
  end

  defp execute_verb(verb, obj_id, player_id, parsed, handler_pid) do
    runtime = Runtime.new(DB.get_snapshot())

    # Build environment
    {:list, items} = args_list = build_args(parsed)

    env = %{
      :runtime => runtime,
      "player" => Value.obj(player_id),
      "this" => Value.obj(obj_id),
      "caller" => Value.obj(player_id),
      "verb" => Value.str(parsed.verb),
      "argstr" => Value.str(parsed.argstr),
      "args" => args_list,
      "dobj" => Value.obj(parsed.dobj_id),
      "dobjstr" => Value.str(parsed.dobj || ""),
      "prepstr" => Value.str(parsed.prep || ""),
      "iobj" => Value.obj(parsed.iobj_id),
      "iobjstr" => Value.str(parsed.iobj || "")
    }

    # Spawn task to execute verb
    task_opts = [
      player: player_id,
      this: obj_id,
      caller: player_id,
      handler_pid: handler_pid,
      args: items,
      verb_name: parsed.verb
    ]

    # Join verb code lines
    code = Enum.join(verb.code, "\n")

    case TaskSupervisor.spawn_task(code, env, task_opts) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        send_error(handler_pid, "Error executing command: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_args(parsed) do
    args = []

    args =
      case parsed.dobj do
        nil -> args
        val -> [Value.str(val) | args]
      end

    args =
      case parsed.prep do
        nil -> args
        val -> [Value.str(val) | args]
      end

    args =
      case parsed.iobj do
        nil -> args
        val -> [Value.str(val) | args]
      end

    Value.list(Enum.reverse(args))
  end

  defp send_error(handler_pid, message) do
    Handler.send_output(handler_pid, message <> "\n")
  end
end
