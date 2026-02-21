defmodule Alchemoo.Command.Executor do
  @moduledoc """
  Executes MOO commands by finding and running verbs.
  """

  alias Alchemoo.Command.Parser
  alias Alchemoo.Connection.Handler
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.TaskSupervisor
  alias Alchemoo.Value

  @doc """
  Execute a command for a player.

  Returns:
    {:ok, task_pid} - Task spawned successfully
    {:error, reason} - Failed to execute
  """
  def execute(command, player_id, handler_pid) do
    # Parse command
    case Parser.parse(command) do
      {:ok, parsed} ->
        execute_parsed(parsed, player_id, handler_pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_parsed(parsed, player_id, handler_pid) do
    # Find verb target
    case Parser.find_verb_target(parsed, player_id, nil) do
      {:ok, obj_id, verb_name} ->
        # Look up verb
        case DB.find_verb(obj_id, verb_name) do
          {:ok, found_obj_id, verb} ->
            # Execute verb
            execute_verb(verb, found_obj_id, player_id, parsed, handler_pid)

          {:error, :E_VERBNF} ->
            # Verb not found, send error
            send_error(handler_pid, "I don't understand that.")
            {:error, :verb_not_found}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp execute_verb(verb, obj_id, player_id, parsed, handler_pid) do
    # Build environment for verb execution
    env = %{
      "player" => Value.obj(player_id),
      "this" => Value.obj(obj_id),
      "caller" => Value.obj(player_id),
      "verb" => Value.str(parsed.verb),
      "argstr" => Value.str(rebuild_argstr(parsed)),
      "args" => build_args(parsed),
      "dobj" => Value.str(parsed.dobj || ""),
      "dobjstr" => Value.str(parsed.dobj || ""),
      "prepstr" => Value.str(parsed.prep || ""),
      "iobj" => Value.str(parsed.iobj || ""),
      "iobjstr" => Value.str(parsed.iobj || "")
    }

    # Spawn task to execute verb
    task_opts = [
      player: player_id,
      this: obj_id,
      caller: player_id,
      handler_pid: handler_pid,
      args: []
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

  defp rebuild_argstr(parsed) do
    [parsed.dobj, parsed.prep, parsed.iobj]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
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
