defmodule Alchemoo.Database.Writer do
  @moduledoc """
  Writes MOO databases in LambdaMOO format for sharing and compatibility.
  """

  @doc """
  Write database to MOO format (Format 4).
  """
  def write_moo(db, path) do
    content = serialize_moo(db)
    File.write(path, content)
  end

  @doc """
  Serialize database to MOO format string.
  """
  def serialize_moo(db) do
    [
      "** LambdaMOO Database, Format Version 4 **",
      "** Exported by Alchemoo **",
      "",
      "#{map_size(db.objects)}",
      # clocks (unused)
      "0",
      "",
      serialize_objects(db.objects),
      # verb programs (we inline them)
      "0",
      # users (unused)
      "0",
      ""
    ]
    |> Enum.join("\n")
  end

  defp serialize_objects(objects) do
    objects
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.map_join("\n", fn {_id, obj} -> serialize_object(obj) end)
  end

  defp serialize_object(obj) do
    [
      "##{obj.id}",
      obj.name,
      # old handles (unused)
      "",
      # flags
      "0",
      "#{obj.owner}",
      "#{obj.location}",
      "#{obj.contents}",
      "#{obj.next}",
      "#{obj.parent}",
      "#{obj.child}",
      "#{obj.sibling}",
      "#{length(obj.verbs)}",
      serialize_verbs(obj.verbs),
      "#{length(obj.properties)}",
      serialize_properties(obj.properties)
    ]
    |> Enum.join("\n")
  end

  defp serialize_verbs(verbs) do
    Enum.map_join(verbs, "\n", &serialize_verb/1)
  end

  defp serialize_verb(verb) do
    [
      verb.name,
      "#{verb.owner}",
      verb.perms,
      "#{verb.prep}",
      serialize_verb_code(verb.code)
    ]
    |> Enum.join("\n")
  end

  defp serialize_verb_code(code) do
    [
      "#{length(code)}",
      Enum.join(code, "\n")
    ]
    |> Enum.join("\n")
  end

  defp serialize_properties(properties) do
    Enum.map_join(properties, "\n", &serialize_property/1)
  end

  defp serialize_property(prop) do
    [
      prop.name,
      serialize_value(prop.value),
      "#{prop.owner}",
      prop.perms
    ]
    |> Enum.join("\n")
  end

  # Clear property
  defp serialize_value(nil), do: "0"
  defp serialize_value(:clear), do: "5"
  defp serialize_value(:none), do: "6"
  defp serialize_value({:num, n}), do: "#{n}"
  defp serialize_value({:obj, n}), do: "##{n}"
  defp serialize_value({:str, s}), do: "\"#{escape_string(s)}\""
  defp serialize_value({:err, err}), do: "E_#{err}"

  defp serialize_value({:list, items}) do
    "{" <> Enum.map_join(items, ", ", &serialize_value/1) <> "}"
  end

  defp escape_string(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
