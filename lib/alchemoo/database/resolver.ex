defmodule Alchemoo.Database.Resolver do
  @moduledoc """
  Resolves symbolic object names like $login, $player, etc.

  In MOO, objects can be referenced by symbolic names starting with $.
  These are resolved by looking for objects whose name starts with $.
  """

  alias Alchemoo.Database.Server, as: DB

  @doc """
  Resolve a symbolic name to an object ID.

  Examples:
    resolve("$login") => {:ok, 10}
    resolve("$player") => {:ok, 6}
    resolve("$nothing") => {:error, :not_found}
  """
  def resolve("$" <> property_name = full_name) do
    # MOO system object resolution: $name means 0.name
    case DB.get_property(0, property_name) do
      {:ok, {:obj, id}} ->
        {:ok, id}

      _ ->
        # Fallback to searching for object with this name
        search_for_object_by_name(full_name)
    end
  end

  def resolve(symbolic_name) when is_binary(symbolic_name) do
    search_for_object_by_name(symbolic_name)
  end

  defp search_for_object_by_name(name) do
    # Get all objects and search for matching name
    snapshot = DB.get_snapshot()

    result =
      Enum.find(snapshot.objects, fn {_id, obj} ->
        obj.name == name
      end)

    case result do
      {id, _obj} -> {:ok, id}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Get a system object by symbolic name (without $ prefix).

  Returns the object ID or -1 if not found.

  Examples:
    object(:login) => 10
    object(:player) => 6
    object(:wizard) => 2
    object(:nothing) => -1
  """
  def object(name) when is_atom(name) do
    case resolve("$#{name}") do
      {:ok, id} -> id
      {:error, :not_found} -> -1
    end
  end
end
