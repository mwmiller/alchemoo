defmodule Alchemoo.Database.Resolver do
  @moduledoc """
  Resolves object names and aliases to object IDs.
  """
  alias Alchemoo.Database.Flags
  alias Alchemoo.Database.Server, as: DB

  @doc """
  Find an object by name or alias in a list of candidate IDs.
  """
  def match(name, candidate_ids, context \\ %{})

  def match(name, candidate_ids, context) when is_binary(name) and is_list(candidate_ids) do
    name = String.trim(name)

    cond do
      name == "" ->
        {:error, :not_found}

      name == "me" ->
        {:ok, Map.get(context, :player, 2)}

      name == "here" ->
        {:ok, Map.get(context, :location, -1)}

      String.starts_with?(name, "#") ->
        resolve_id(name)

      true ->
        search_candidates(name, candidate_ids)
    end
  end

  def match(_name, _candidates, _context), do: {:error, :not_found}

  @doc """
  Specialized match for players by name.
  """
  def player(name) do
    # In a real MOO, players are usually indexed.
    # For now, we search all players.
    all_players = list_all_players()
    match(name, all_players)
  end

  @doc """
  Resolve a symbolic name (e.g. "$login") or object ID.
  """
  def resolve(<<"$", name::binary>>) do
    object(String.to_atom(name))
  end

  def resolve(name) when is_binary(name) do
    case match(name, []) do
      {:ok, id} -> id
      _ -> -1
    end
  end

  @doc """
  Find a core object by name (e.g. $player, $room).
  """
  def object(name) when is_atom(name) do
    # Core objects are properties on #0
    case DB.get_property(0, Atom.to_string(name)) do
      {:ok, {:obj, id}} -> id
      _ -> fallback_object(name)
    end
  end

  @doc """
  List all symbolic aliases defined on object #0.
  """
  def list_aliases do
    case DB.get_object(0) do
      {:ok, obj} ->
        # Core aliases are properties on #0 that have object values
        aliases = Enum.reduce(obj.properties, %{}, &extract_obj_prop/2)

        # Also include overridden properties if any
        Enum.reduce(obj.overridden_properties, aliases, fn {name, prop}, acc ->
          extract_obj_prop(%{name: name, value: prop.value}, acc)
        end)

      _ ->
        %{}
    end
  end

  defp extract_obj_prop(prop, acc) do
    case prop.value do
      {:obj, id} -> Map.put(acc, prop.name, id)
      _ -> acc
    end
  end

  defp resolve_id("#" <> id_str) do
    case Integer.parse(id_str) do
      {id, ""} -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  defp search_candidates(name, ids) do
    Enum.find_value(ids, {:error, :not_found}, fn id ->
      with {:ok, obj} <- DB.get_object(id),
           true <- matches_object?(obj, name) do
        {:ok, id}
      else
        _ -> nil
      end
    end)
  end

  defp matches_object?(obj, name) do
    lower_name = String.downcase(name)

    actual_name =
      case DB.get_property(obj.id, "name") do
        {:ok, {:str, n}} -> n
        _ -> obj.name
      end

    case String.downcase(actual_name) == lower_name do
      true -> true
      false -> matches_aliases?(obj, lower_name)
    end
  end

  defp matches_aliases?(obj, lower_name) do
    case DB.get_property(obj.id, "aliases") do
      {:ok, {:list, aliases}} ->
        Enum.any?(aliases, fn
          {:str, a} -> String.downcase(a) == lower_name
          _ -> false
        end)

      _ ->
        false
    end
  end

  defp list_all_players do
    # Get all user objects
    DB.get_snapshot().objects
    |> Map.values()
    |> Enum.filter(fn obj ->
      Flags.set?(obj.flags, Flags.user())
    end)
    |> Enum.map(& &1.id)
  end

  defp fallback_object(:player), do: 6
  defp fallback_object(:room), do: 3
  defp fallback_object(:login), do: 0
  defp fallback_object(:network), do: 0
  defp fallback_object(_), do: -1
end
