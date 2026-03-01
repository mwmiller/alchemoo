defmodule Alchemoo.Database.Permissions do
  @moduledoc """
  Implements MOO-compatible permission checks for objects, properties, and verbs.
  """
  alias Alchemoo.Database.Flags
  import Bitwise

  # Property and Verb flag bits
  @read 0x01
  @write 0x02
  @chown 0x04
  @exec 0x04
  @debug 0x08

  def read, do: @read
  def write, do: @write
  def chown, do: @chown
  def exec, do: @exec
  def debug, do: @debug

  alias Alchemoo.Database.Server, as: DBServer

  @doc """
  Returns true if the player has enough permissions to perform the operation on the object.
  """
  def object_allows?(object, player_id, flag) do
    # Wizards and owners can always do anything
    # Otherwise, check the object's flags
    wizard?(player_id) or
      object.owner == player_id or
      Flags.set?(object.flags, flag)
  end

  @doc """
  Returns true if the player has enough permissions to perform the operation on the property.
  """
  def property_allows?(property, player_id, flag) do
    # Wizards and owners can always do anything
    # Otherwise, check the property's perms
    wizard?(player_id) or
      property.owner == player_id or
      perms_set?(property.perms, flag)
  end

  @doc """
  Returns true if the player has enough permissions to perform the operation on the verb.
  """
  def verb_allows?(verb, player_id, flag) do
    # Wizards and owners can always do anything
    # Otherwise, check the verb's perms
    wizard?(player_id) or
      verb.owner == player_id or
      perms_set?(verb.perms, flag)
  end

  @doc """
  Helper to check if a player ID belongs to a wizard.
  """
  def wizard?(player_id) do
    case DBServer.get_object(player_id) do
      {:ok, obj} -> Flags.set?(obj.flags, Flags.wizard())
      _ -> false
    end
  end

  # Internal: check if permission bits are set
  # Handle both numeric perms (from DB) and string perms (if any)
  defp perms_set?(perms, flag) when is_integer(perms), do: (perms &&& flag) != 0

  defp perms_set?(perms, flag) when is_binary(perms) do
    chars =
      case flag do
        @read -> ["r"]
        @write -> ["w"]
        @chown -> ["c", "x"]
        @debug -> ["d"]
        _ -> []
      end

    Enum.any?(chars, &String.contains?(perms, &1))
  end

  defp perms_set?(_, _), do: false
end
