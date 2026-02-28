defmodule Alchemoo.Builtins.SSH do
  @moduledoc """
  SSH management built-in functions.
  """
  alias Alchemoo.Auth.SSH, as: AuthSSH
  alias Alchemoo.Database.Flags
  alias Alchemoo.Database.Server, as: DBServer
  alias Alchemoo.Value

  @doc "ssh_add_key(player, key_string)"
  def ssh_add_key([{:obj, player_id}, {:str, key_string}], _env) do
    if can_manage_ssh?(player_id) do
      case AuthSSH.add_key(player_id, key_string) do
        :ok -> Value.num(1)
        {:error, _} -> Value.err(:E_INVARG)
      end
    else
      Value.err(:E_PERM)
    end
  end

  def ssh_add_key(_, _env), do: Value.err(:E_ARGS)

  @doc "ssh_remove_key(player, index)"
  def ssh_remove_key([{:obj, player_id}, {:num, index}], _env) do
    if can_manage_ssh?(player_id) do
      case AuthSSH.remove_key(player_id, index) do
        :ok -> Value.num(1)
        {:error, :E_RANGE} -> Value.err(:E_RANGE)
        {:error, _} -> Value.err(:E_INVARG)
      end
    else
      Value.err(:E_PERM)
    end
  end

  def ssh_remove_key(_, _env), do: Value.err(:E_ARGS)

  @doc "ssh_list_keys(player)"
  def ssh_list_keys([{:obj, player_id}], _env) do
    if can_manage_ssh?(player_id) do
      keys = AuthSSH.list_keys(player_id)

      Value.list(
        Enum.map(keys, fn [type, art, fingerprint] ->
          Value.list([Value.str(type), Value.str(art), Value.str(fingerprint)])
        end)
      )
    else
      Value.err(:E_PERM)
    end
  end

  def ssh_list_keys(_, _env), do: Value.err(:E_ARGS)

  @doc "ssh_key_info(player, index)"
  def ssh_key_info([{:obj, player_id}, {:num, index}], _env) do
    if can_manage_ssh?(player_id) do
      keys = AuthSSH.list_keys(player_id)

      if index >= 1 and index <= length(keys) do
        [type, art, fingerprint] = Enum.at(keys, index - 1)
        Value.list([Value.str(type), Value.str(art), Value.str(fingerprint)])
      else
        Value.err(:E_RANGE)
      end
    else
      Value.err(:E_PERM)
    end
  end

  def ssh_key_info(_, _env), do: Value.err(:E_ARGS)

  defp can_manage_ssh?(player_id) do
    # Per standard MOO, we check the current task permissions (perms)
    # caller_perms() is the perms of the caller, but perms is what we use
    # for authorization of the current operation.
    perms = get_task_context(:perms) || -1

    # Check if perms is wizard
    is_wizard =
      case DBServer.get_object(perms) do
        {:ok, obj} -> Flags.set?(obj.flags, Flags.wizard())
        _ -> false
      end

    is_wizard or perms == player_id
  end

  defp get_task_context(key) do
    case Process.get(:task_context) do
      nil -> nil
      context -> Map.get(context, key)
    end
  end
end
