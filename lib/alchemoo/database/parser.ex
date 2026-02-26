defmodule Alchemoo.Database.Parser do
  @moduledoc """
  Parses LambdaMOO database files (Format Version 4).
  """
  require Logger
  require Bitwise

  alias Alchemoo.Database
  alias Alchemoo.Database.{Object, Property, Verb}
  alias Alchemoo.Value

  def parse_file(path) do
    with {:ok, content} <- File.read(path) do
      parse(content)
    end
  end

  def parse(content) do
    lines = String.split(content, ~r/\r?\n/)
    do_parse(lines)
  end

  defp do_parse(lines) do
    with {:ok, version, lines} <- parse_header(lines),
         {:ok, metadata, lines} <- parse_metadata(lines, version),
         {:ok, objects, lines} <- parse_objects(lines, metadata.object_count, version),
         {:ok, objects} <- parse_verb_code(lines, objects) do
      # Track max_object from the actual parsed IDs
      max_id = Map.keys(objects) |> Enum.max(fn -> -1 end)

      # Post-process to build full property maps
      objects = build_relationship_lists(objects)
      objects = resolve_properties(objects)

      {:ok,
       %Database{
         version: version,
         object_count: metadata.object_count,
         clock: 0,
         objects: objects,
         max_object: max_id
       }}
    end
  end

  defp parse_header([line | rest]) do
    case Regex.run(~r/Format Version (\d+)/, line) do
      [_, version] -> {:ok, String.to_integer(version), rest}
      _ -> {:error, :invalid_header}
    end
  end

  defp parse_metadata(lines, version) when version >= 4 do
    with [obj_count_str, _verb_count, _dummy, user_count_str | rest] <- lines,
         {obj_count, _} <- Integer.parse(obj_count_str),
         {user_count, _} <- Integer.parse(user_count_str) do
      rest = Enum.drop(rest, user_count)
      # Format 4 metadata can have more numbers until #0
      rest = skip_to_first_object(rest)
      {:ok, %{object_count: obj_count, version: version}, rest}
    else
      _ -> {:error, :invalid_metadata}
    end
  end

  defp skip_to_first_object(["#" <> _ | _] = lines), do: lines
  defp skip_to_first_object([_ | rest]), do: skip_to_first_object(rest)
  defp skip_to_first_object([]), do: []

  defp parse_objects(lines, count, version) do
    parse_objects_loop(lines, count, version, %{})
  end

  defp parse_objects_loop(lines, 0, _v, acc), do: {:ok, acc, lines}

  defp parse_objects_loop(lines, count, version, acc) do
    case parse_object(lines, version) do
      {:ok, obj, rest} ->
        parse_objects_loop(rest, count - 1, version, Map.put(acc, obj.id, obj))

      err ->
        err
    end
  end

  defp parse_object(["#" <> id_str | rest], _version) do
    with {:ok, id} <- parse_id(id_str),
         {:ok, name, rest} <- next_line(rest),
         {:ok, _handles, rest} <- next_line(rest),
         {:ok, flags, rest} <- parse_integer_line(rest),
         {:ok, owner, rest} <- parse_integer_line(rest),
         {:ok, location, rest} <- parse_integer_line(rest),
         {:ok, contents, rest} <- parse_integer_line(rest),
         {:ok, next, rest} <- parse_integer_line(rest),
         {:ok, parent, rest} <- parse_integer_line(rest),
         {:ok, child, rest} <- parse_integer_line(rest),
         {:ok, sibling, rest} <- parse_integer_line(rest),
         {:ok, verbs, rest} <- parse_verbs(rest),
         {:ok, {local_names, values}, rest} <- parse_properties(rest) do
      obj = %Object{
        id: id,
        name: name,
        flags: flags,
        owner: owner,
        location: location,
        parent: parent,
        verbs: verbs,
        properties: local_names |> Enum.map(&%Property{name: &1}),
        # Store raw values for post-processing
        temp_values: values,
        first_content_id: contents,
        next_id: next,
        first_child_id: child,
        sibling_id: sibling
      }

      {:ok, obj, rest}
    end
  end

  defp parse_id(s) do
    case Integer.parse(String.trim(s)) do
      {id, _} -> {:ok, id}
      _ -> {:error, :invalid_id}
    end
  end

  defp next_line([line | rest]), do: {:ok, line, rest}
  defp next_line([]), do: {:error, :unexpected_eof}

  defp parse_integer_line([line | rest]) do
    case Integer.parse(String.trim(line)) do
      {n, _} -> {:ok, n, rest}
      _ -> {:error, {:expected_int, line}}
    end
  end

  defp parse_verbs([count_line | rest]) do
    {count, _} = Integer.parse(String.trim(count_line))
    parse_verbs_loop(rest, count, [])
  end

  defp parse_verbs_loop(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp parse_verbs_loop([name, owner_str, perms_str, prep_str | rest], count, acc) do
    verb = %Verb{
      name: name,
      owner: String.to_integer(String.trim(owner_str)),
      perms: String.to_integer(String.trim(perms_str)),
      prep: String.to_integer(String.trim(prep_str)),
      args: {:this, :none, :none},
      code: []
    }

    parse_verbs_loop(rest, count - 1, [verb | acc])
  end

  defp parse_properties([count_line | rest]) do
    {count, _} = Integer.parse(String.trim(count_line))
    {:ok, names, rest} = parse_names(rest, count, [])
    {:ok, val_count_line, rest} = next_line(rest)
    {val_count, _} = Integer.parse(String.trim(val_count_line))
    {:ok, values, rest} = parse_values(rest, val_count, [])
    {:ok, {names, values}, rest}
  end

  defp parse_names(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}
  defp parse_names([name | rest], count, acc), do: parse_names(rest, count - 1, [name | acc])

  defp parse_values(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp parse_values(lines, count, acc) do
    with {:ok, val, rest} <- parse_value(lines),
         [owner_str, perms_str | rest] <- rest,
         {owner, _} <- Integer.parse(String.trim(owner_str)),
         {perms, _} <- Integer.parse(String.trim(perms_str)) do
      parse_values(rest, count - 1, [{val, owner, perms} | acc])
    else
      _ -> {:error, :invalid_property_value}
    end
  end

  defp parse_value([type_str | rest]) do
    {type_code, _} = Integer.parse(String.trim(type_str))
    base_type = Bitwise.band(type_code, 0x1F)

    case Bitwise.band(type_code, 0x20) != 0 do
      true ->
        [id_str | rest] = rest
        {:ok, Value.num(String.to_integer(String.trim(id_str))), rest}

      false ->
        dispatch_value(base_type, rest)
    end
  end

  defp dispatch_value(0, [s | rest]),
    do: {:ok, Value.num(String.to_integer(String.trim(s))), rest}

  defp dispatch_value(1, [s | rest]),
    do: {:ok, Value.obj(String.to_integer(String.trim(s))), rest}

  defp dispatch_value(2, [s | rest]), do: {:ok, Value.str(s), rest}

  defp dispatch_value(3, [s | rest]) do
    err_code = String.to_integer(String.trim(s))
    {:ok, Value.err(code_to_error(err_code)), rest}
  end

  defp dispatch_value(4, [count_str | rest]) do
    {count, _} = Integer.parse(String.trim(count_str))
    parse_list_elements(rest, count, [])
  end

  defp dispatch_value(5, rest), do: {:ok, :clear, rest}
  defp dispatch_value(6, rest), do: {:ok, :none, rest}
  defp dispatch_value(9, [s | rest]), do: {:ok, {:float, s}, rest}

  defp code_to_error(0), do: :E_NONE
  defp code_to_error(1), do: :E_TYPE
  defp code_to_error(2), do: :E_DIV
  defp code_to_error(3), do: :E_PERM
  defp code_to_error(4), do: :E_PROPNF
  defp code_to_error(5), do: :E_VERBNF
  defp code_to_error(6), do: :E_VARNF
  defp code_to_error(7), do: :E_INVIND
  defp code_to_error(8), do: :E_RECMOVE
  defp code_to_error(9), do: :E_MAXREC
  defp code_to_error(10), do: :E_RANGE
  defp code_to_error(11), do: :E_ARGS
  defp code_to_error(12), do: :E_NACC
  defp code_to_error(13), do: :E_INVARG
  defp code_to_error(14), do: :E_QUOTA
  defp code_to_error(15), do: :E_FLOAT
  defp code_to_error(_), do: :E_NONE

  defp parse_list_elements(rest, 0, acc), do: {:ok, Value.list(Enum.reverse(acc)), rest}

  defp parse_list_elements(lines, count, acc) do
    {:ok, val, rest} = parse_value(lines)
    parse_list_elements(rest, count - 1, [val | acc])
  end

  defp parse_verb_code(lines, objects) do
    lines = skip_to_verb_code(lines)
    parse_verb_code_loop(lines, objects)
  end

  defp skip_to_verb_code([line | rest] = lines) do
    if Regex.match?(~r/^#\d+:\d+$/, String.trim(line)), do: lines, else: skip_to_verb_code(rest)
  end

  defp skip_to_verb_code([]), do: []

  defp parse_verb_code_loop([], objects), do: {:ok, objects}

  defp parse_verb_code_loop(["#" <> ref | rest], objects) do
    [obj_id_str, verb_idx_str] = String.split(ref, ":")
    obj_id = String.to_integer(obj_id_str)
    verb_idx = String.to_integer(verb_idx_str)
    {:ok, code, rest} = parse_code_block(rest, [])
    objects = update_verb_code(objects, obj_id, verb_idx, code)
    parse_verb_code_loop(rest, objects)
  end

  defp parse_verb_code_loop([_ | rest], objects), do: parse_verb_code_loop(rest, objects)

  defp parse_code_block(["." | rest], acc), do: {:ok, Enum.reverse(acc), rest}
  defp parse_code_block([line | rest], acc), do: parse_code_block(rest, [line | acc])
  defp parse_code_block([], acc), do: {:ok, Enum.reverse(acc), []}

  defp update_verb_code(objects, id, idx, code) do
    if obj = objects[id] do
      verbs = List.update_at(obj.verbs, idx, &%{&1 | code: code})
      Map.put(objects, id, %{obj | verbs: verbs})
    else
      objects
    end
  end

  defp build_relationship_lists(objects) do
    # Build children and contents maps in one pass
    {children_map, contents_map} =
      Enum.reduce(objects, {%{}, %{}}, fn {id, obj}, {c_acc, l_acc} ->
        c_acc =
          if obj.parent >= 0, do: Map.update(c_acc, obj.parent, [id], &[id | &1]), else: c_acc

        l_acc =
          if obj.location >= 0, do: Map.update(l_acc, obj.location, [id], &[id | &1]), else: l_acc

        {c_acc, l_acc}
      end)

    # Apply maps to objects
    Enum.into(objects, %{}, fn {id, obj} ->
      {id, %{obj | children: children_map[id] || [], contents: contents_map[id] || []}}
    end)
  end

  defp resolve_properties(objects) do
    # Resolve properties using a memoized topological approach.
    # We must ensure parents are resolved before children.
    resolve_recursive(Map.keys(objects), objects, %{})
  end

  defp resolve_recursive([], _objects, resolved), do: resolved

  defp resolve_recursive([id | rest], objects, resolved) do
    if Map.has_key?(resolved, id) do
      resolve_recursive(rest, objects, resolved)
    else
      obj = objects[id]

      # Resolve parent first if needed
      resolved =
        if obj.parent >= 0 and not Map.has_key?(resolved, obj.parent) do
          resolve_recursive([obj.parent], objects, resolved)
        else
          resolved
        end

      parent_props = if obj.parent >= 0, do: resolved[obj.parent].all_properties, else: []

      # RULE: local properties first, then inherited
      {local_values, inherited_values} = Enum.split(obj.temp_values, length(obj.properties))

      local_properties =
        Enum.zip(obj.properties, local_values)
        |> Enum.map(fn {p, {v, o, perms}} ->
          %{p | value: v, owner: o, perms: Integer.to_string(perms)}
        end)

      overridden =
        Enum.zip(parent_props, inherited_values)
        |> Enum.into(%{}, fn {p, {v, o, perms}} ->
          {p.name, %{p | value: v, owner: o, perms: Integer.to_string(perms)}}
        end)

      updated_obj = %{
        obj
        | properties: local_properties,
          overridden_properties: overridden,
          all_properties: local_properties ++ parent_props
      }

      resolve_recursive(rest, objects, Map.put(resolved, id, updated_obj))
    end
  end
end
