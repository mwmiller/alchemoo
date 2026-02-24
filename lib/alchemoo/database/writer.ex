defmodule Alchemoo.Database.Writer do
  @moduledoc """
  Serializes the database back to MOO format.
  """
  alias Alchemoo.Database
  alias Alchemoo.Database.Object

  def write_moo(%Database{} = db, path) do
    content = serialize_moo(db)
    File.write(path, content)
  end

  def serialize_moo(%Database{} = db) do
    header = [
      "** LambdaMOO Database, Format Version 4 **",
      "** Exported by Alchemoo **",
      "#{map_size(db.objects)} objects",
      "#{count_all_verbs(db)} verbs",
      "0",
      "#{count_players(db)} users"
    ]

    # Add player list
    player_list = get_player_list(db)

    # Add objects
    objects =
      db.objects
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map_join("\n", &serialize_object/1)

    Enum.join(header ++ player_list, "\n") <> "\n" <> objects
  end

  defp count_all_verbs(db) do
    db.objects |> Map.values() |> Enum.map(&length(&1.verbs)) |> Enum.sum()
  end

  defp count_players(db) do
    db.objects |> Map.values() |> Enum.count(&is_player?/1)
  end

  defp get_player_list(db) do
    db.objects
    |> Map.values()
    |> Enum.filter(&is_player?/1)
    |> Enum.map(&"##{&1.id}")
  end

  defp is_player?(obj) do
    Alchemoo.Database.Flags.set?(obj.flags, Alchemoo.Database.Flags.user())
  end

  defp serialize_object(%Object{} = obj) do
    header = [
      "##{obj.id}",
      obj.name,
      # handles
      "",
      "#{obj.flags}",
      "#{obj.owner}",
      "#{obj.location}",
      "#{obj.first_content_id}",
      "#{obj.next_id}",
      "#{obj.parent}",
      "#{obj.first_child_id}",
      "#{obj.sibling_id}"
    ]

    verbs_header = ["#{length(obj.verbs)}"]
    verbs = Enum.map(obj.verbs, &serialize_verb/1)

    props_header = ["#{length(obj.properties)}"]
    prop_names = Enum.map(obj.properties, & &1.name)
    prop_values = Enum.map(obj.properties, &serialize_property/1)

    Enum.join(header ++ verbs_header ++ verbs ++ props_header ++ prop_names ++ prop_values, "\n")
  end

  defp serialize_verb(verb) do
    [
      verb.name,
      "#{verb.owner}",
      "#{verb.perms}",
      "#{verb.prep}",
      serialize_code(verb.code)
    ]
    |> Enum.join("\n")
  end

  defp serialize_code(code) do
    Enum.join(code, "\n") <> "\n."
  end

  defp serialize_property(prop) do
    [
      serialize_value(prop.value),
      "#{prop.owner}",
      "#{prop.perms}"
    ]
    |> Enum.join("\n")
  end

  defp serialize_value(val) do
    case val do
      {:num, n} -> "0\n#{n}"
      {:obj, n} -> "1\n#{n}"
      {:str, s} -> "2\n#{s}"
      {:err, e} -> "3\n#{error_to_code(e)}"
      {:list, items} -> "4\n#{length(items)}\n#{Enum.map_join(items, "\n", &serialize_value/1)}"
      # Should not happen in export
      :clear -> "0\n0"
    end
  end

  defp error_to_code(e) do
    case e do
      :E_NONE -> 0
      :E_TYPE -> 1
      :E_DIV -> 2
      :E_PERM -> 3
      :E_PROPNF -> 4
      :E_VERBNF -> 5
      :E_VARNF -> 6
      :E_INVIND -> 7
      :E_RECMOVE -> 8
      :E_MAXREC -> 9
      :E_RANGE -> 10
      :E_ARGS -> 11
      :E_NACC -> 12
      :E_INVARG -> 13
      :E_QUOTA -> 14
      :E_FLOAT -> 15
    end
  end
end
