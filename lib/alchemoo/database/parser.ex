defmodule Alchemoo.Database.Parser do
  @moduledoc """
  Parses LambdaMOO database files (prioritizing Format Version 4).

  The database format consists of:
  1. Header with version and metadata
  2. Object definitions (structure, verb names, property names)
  3. Verb code sections (#objnum:verbnum)
  4. Footer with clocks and queued tasks

  Note: Versions older than Format 4 (as used by LambdaCore) are not a priority.
  """
  require Logger
  import Bitwise

  alias Alchemoo.Database
  alias Alchemoo.Database.{Object, Property, Verb}
  alias Alchemoo.Value

  @doc """
  Parses a LambdaMOO database file.

  ## Examples

      iex> Alchemoo.Database.Parser.parse_file("Minimal.db")
      {:ok, %Alchemoo.Database{}}
  """
  def parse_file(path) do
    with {:ok, content} <- File.read(path) do
      parse(content)
    end
  end

  @doc """
  Parses LambdaMOO database content from a string.
  """
  def parse(content) do
    lines = String.split(content, ~r/\r?\n/)

    do_parse(lines)
  end

  defp do_parse(lines) do
    with {:ok, version, lines} <- parse_header(lines),
         {:ok, metadata, lines} <- parse_metadata(lines, version),
         {:ok, objects, lines} <- parse_objects(lines, metadata),
         {:ok, objects_with_code} <- parse_verb_code(lines, objects) do
      # Post-process: convert linked lists to Elixir lists AND resolve inherited property names
      objects_with_lists = build_relationship_lists(objects_with_code)
      objects_final = resolve_all_properties(objects_with_lists)

      {:ok,
       %Database{
         version: version,
         object_count: metadata.object_count,
         clock: metadata.clock,
         objects: objects_final,
         max_object: Enum.max(Map.keys(objects_final), fn -> -1 end)
       }}
    end
  end

  defp build_relationship_lists(objects) do
    # For each object, follow the sibling/next chains to build children/contents lists
    Enum.into(objects, %{}, fn {id, obj} ->
      {id,
       %{
         obj
         | children: collect_chain(objects, obj.first_child_id, :sibling_id),
           contents: collect_chain(objects, obj.first_content_id, :next_id)
       }}
    end)
  end

  defp collect_chain(_objects, -1, _field), do: []

  defp collect_chain(objects, id, field) do
    case Map.get(objects, id) do
      nil ->
        []

      obj ->
        [id | collect_chain(objects, Map.get(obj, field), field)]
    end
  end

  defp resolve_all_properties(objects) do
    # For each object, inherited values are stored as a list in temp_inherited_values.
    # We need to map them to actual property names from ancestors.
    Enum.into(objects, %{}, fn {id, obj} ->
      {id, resolve_obj_properties(obj, objects)}
    end)
  end

  defp resolve_obj_properties(obj, objects) do
    # Get inherited names from ancestors
    inherited_names = get_inherited_property_names(obj.parent, objects)

    # Map inherited values to names
    overridden =
      Enum.zip(inherited_names, Map.get(obj, :temp_inherited_values, []) || [])
      |> Enum.into(%{}, fn {name, {value, owner, perms}} ->
        {name, %Property{name: name, value: value, owner: owner, perms: perms}}
      end)

    %{obj | overridden_properties: overridden}
  end

  defp get_inherited_property_names(-1, _objects), do: []

  defp get_inherited_property_names(parent_id, objects) do
    case Map.get(objects, parent_id) do
      nil ->
        []

      parent ->
        # Names from ancestors + local names of this parent
        get_inherited_property_names(parent.parent, objects) ++
          Enum.map(parent.properties, & &1.name)
    end
  end

  # Parse header: "** LambdaMOO Database, Format Version N **"
  defp parse_header([line | rest]) do
    case Regex.run(~r/Format Version (\d+)/, line) do
      [_, version] -> {:ok, String.to_integer(version), rest}
      _ -> {:error, :invalid_header}
    end
  end

  # Parse metadata based on version
  defp parse_metadata(lines, version) when version >= 4 do
    # Format 4:
    # 1. object_count
    # 2. verb_count
    # 3. dummy
    # 4. user_count
    # 5. users (user_count lines)

    with [obj_count_str | rest] <- lines,
         {object_count, _} <- Integer.parse(obj_count_str),
         [_verb_count | rest] <- rest,
         [_dummy1 | rest] <- rest,
         [user_count_str | rest] <- rest,
         {user_count, _} <- Integer.parse(user_count_str) do
      # Skip user IDs
      rest = Enum.drop(rest, user_count)
      # Sometimes there's more metadata (numbers) until #0
      rest = skip_to_first_object(rest)

      {:ok, %{object_count: object_count, clock: 0, version: version}, rest}
    else
      _ -> {:error, :invalid_metadata}
    end
  end

  defp parse_metadata(_lines, version) do
    {:error, {:unsupported_version, version}}
  end

  defp skip_to_first_object(["#" <> _ | _] = lines), do: lines
  defp skip_to_first_object([_ | rest]), do: skip_to_first_object(rest)
  defp skip_to_first_object([]), do: []

  # Parse all objects
  defp parse_objects(lines, metadata) do
    parse_objects_loop(lines, metadata.object_count, metadata, %{})
  end

  defp parse_objects_loop(lines, 0, _metadata, acc), do: {:ok, acc, lines}

  defp parse_objects_loop(lines, remaining, metadata, acc) do
    case parse_object(lines, metadata.version) do
      {:ok, object, rest} ->
        parse_objects_loop(rest, remaining - 1, metadata, Map.put(acc, object.id, object))

      {:error, _} = error ->
        error
    end
  end

  # Parse a single object
  defp parse_object(["" | rest], version), do: parse_object(rest, version)

  defp parse_object(["#" <> id_str | rest], version) do
    with {:ok, id} <- parse_integer(id_str),
         {:ok, name, rest} <- parse_line(rest),
         # Both Format 1 and Format 4 have an extra line after the name (handles), usually empty
         {:ok, _handles, rest} <- parse_line(rest),
         {:ok, flags, rest} <- parse_flags_line(rest),
         {:ok, owner, rest} <- parse_integer_line(rest),
         {:ok, location, rest} <- parse_integer_line(rest),
         {:ok, first_content_id, rest} <- parse_integer_line(rest),
         {:ok, next_id, rest} <- parse_integer_line(rest),
         {:ok, parent, rest} <- parse_integer_line(rest),
         {:ok, first_child_id, rest} <- parse_integer_line(rest),
         {:ok, sibling_id, rest} <- parse_integer_line(rest),
         {:ok, verbs, rest} <- parse_verb_headers(rest),
         {:ok, {properties, inherited_values}, rest} <- parse_property_headers(rest, version) do
      object = %Object{
        id: id,
        name: name,
        flags: flags,
        owner: owner,
        location: location,
        first_content_id: first_content_id,
        next_id: next_id,
        parent: parent,
        first_child_id: first_child_id,
        sibling_id: sibling_id,
        verbs: verbs,
        properties: properties
      }

      object = Map.put(object, :temp_inherited_values, inherited_values)

      {:ok, object, rest}
    end
  end

  defp parse_object(lines, _version) do
    {:error, {:invalid_object_start, Enum.take(lines, 5)}}
  end

  # Parse verb headers (name and metadata, code comes later)
  defp parse_verb_headers([count_line | rest]) do
    case Integer.parse(String.trim(count_line)) do
      {count, _} -> parse_verb_headers_loop(rest, count, [])
      :error -> {:error, :invalid_verb_count}
    end
  end

  defp parse_verb_headers_loop(lines, 0, acc), do: {:ok, Enum.reverse(acc), lines}

  defp parse_verb_headers_loop(lines, remaining, acc) do
    case parse_verb_header_multiline(lines) do
      {:ok, verb, rest} ->
        parse_verb_headers_loop(rest, remaining - 1, [verb | acc])

      {:error, _} = error ->
        error
    end
  end

  defp parse_verb_header_multiline([name, owner, perms, prep | rest]) do
    with {owner_int, _} <- Integer.parse(String.trim(owner)),
         {perms_int, _} <- Integer.parse(String.trim(perms)),
         {prep_int, _} <- Integer.parse(String.trim(prep)) do
      {:ok,
       %Verb{
         name: String.trim(name),
         owner: owner_int,
         perms: perms_int,
         prep: prep_int,
         args: {:this, :none, :none},
         code: []
       }, rest}
    else
      _ -> {:error, :invalid_verb_header}
    end
  end

  defp parse_verb_header_multiline(lines) do
    {:error, {:invalid_verb_header, lines}}
  end

  defp parse_property_headers([count_line | rest], version) do
    case Integer.parse(String.trim(count_line)) do
      {count, _} ->
        {:ok, names, rest} = parse_property_names(rest, count, [])
        process_property_values(rest, names, count, version)

      :error ->
        {:error, {:invalid_property_count, count_line}}
    end
  end

  defp process_property_values([val_count_line | rest], names, count, _version) do
    case Integer.parse(String.trim(val_count_line)) do
      {val_count, _} ->
        case parse_property_values(rest, val_count, []) do
          {:ok, values, rest} ->
            {properties, inherited} = map_property_values(names, values, count, val_count)
            {:ok, {properties, inherited}, rest}

          {:error, reason} ->
            {:error, reason}
        end

      :error ->
        {:error, {:invalid_property_value_count, val_count_line}}
    end
  end

  defp map_property_values(names, values, count, val_count) do
    # Inherited properties are at the beginning
    num_inherited = max(0, val_count - count)
    inherited_values = Enum.take(values, num_inherited)

    # Local properties are at the end
    local_values = Enum.drop(values, num_inherited)

    properties =
      Enum.zip(names, local_values)
      |> Enum.map(fn {name, {value, owner, perms}} ->
        %Property{
          name: name,
          value: value,
          owner: owner,
          perms: Integer.to_string(perms)
        }
      end)

    {properties, inherited_values}
  end

  defp parse_property_names(lines, 0, acc), do: {:ok, Enum.reverse(acc), lines}

  defp parse_property_names([name | rest], remaining, acc) do
    parse_property_names(rest, remaining - 1, [String.trim(name) | acc])
  end

  defp parse_property_values(lines, 0, acc), do: {:ok, Enum.reverse(acc), lines}

  defp parse_property_values(lines, remaining, acc) do
    case parse_value(lines) do
      {:ok, value, [owner_str, perms_str | rest]} ->
        with {owner, _} <- Integer.parse(String.trim(owner_str)),
             {perms, _} <- Integer.parse(String.trim(perms_str)) do
          parse_property_values(rest, remaining - 1, [{value, owner, perms} | acc])
        else
          _ -> {:error, {:invalid_property_metadata, owner_str, perms_str}}
        end

      _ ->
        {:error, :unexpected_eof_in_property_values}
    end
  end

  defp parse_value([]), do: {:error, :unexpected_eof}

  defp parse_value([type_str | rest]) do
    case Integer.parse(String.trim(type_str)) do
      {type_code, _} ->
        # Modern MOO uses 0x20 bit for 'shared' flag
        base_type = band(type_code, 0x1F)

        # Check for shared flag (0x20)
        if band(type_code, 0x20) != 0 do
          # Shared value: read one integer ID and treat as numerical value for now
          [id_str | next_rest] = rest
          {:ok, Value.num(String.to_integer(String.trim(id_str))), next_rest}
        else
          dispatch_value(base_type, rest, type_str)
        end

      :error ->
        {:error, {:invalid_type_code, type_str}}
    end
  end

  defp dispatch_value(0, rest, _), do: parse_num(rest)
  defp dispatch_value(1, rest, _), do: parse_obj_ref(rest)
  defp dispatch_value(2, rest, _), do: parse_str(rest)
  defp dispatch_value(3, rest, _), do: parse_err(rest)
  defp dispatch_value(4, rest, _), do: parse_list_db(rest)
  defp dispatch_value(5, rest, _), do: {:ok, :clear, rest}
  defp dispatch_value(6, rest, _), do: {:ok, :none, rest}
  defp dispatch_value(9, rest, _), do: parse_float(rest)
  defp dispatch_value(_, _, type_str), do: {:error, {:unknown_type, type_str}}

  defp parse_num([val_str | rest]),
    do: {:ok, Value.num(String.to_integer(String.trim(val_str))), rest}

  defp parse_num([]), do: {:error, :unexpected_eof}

  defp parse_obj_ref([val_str | rest]),
    do: {:ok, Value.obj(String.to_integer(String.trim(val_str))), rest}

  defp parse_obj_ref([]), do: {:error, :unexpected_eof}

  defp parse_str([val_str | rest]), do: {:ok, Value.str(val_str), rest}
  defp parse_str([]), do: {:error, :unexpected_eof}

  defp parse_err([val_str | rest]) do
    err_atom = map_error_code(String.trim(val_str))
    {:ok, Value.err(err_atom), rest}
  end

  defp parse_err([]), do: {:error, :unexpected_eof}

  defp map_error_code("0"), do: :E_NONE
  defp map_error_code("1"), do: :E_TYPE
  defp map_error_code("2"), do: :E_DIV
  defp map_error_code("3"), do: :E_PERM
  defp map_error_code("4"), do: :E_PROPNF
  defp map_error_code("5"), do: :E_VERBNF
  defp map_error_code("6"), do: :E_VARNF
  defp map_error_code("7"), do: :E_INVIND
  defp map_error_code("8"), do: :E_RECMOVE
  defp map_error_code("9"), do: :E_MAXREC
  defp map_error_code("10"), do: :E_RANGE
  defp map_error_code("11"), do: :E_ARGS
  defp map_error_code("12"), do: :E_NACC
  defp map_error_code("13"), do: :E_INVARG
  defp map_error_code("14"), do: :E_QUOTA
  defp map_error_code("15"), do: :E_FLOAT
  defp map_error_code(_), do: :E_NONE

  defp parse_list_db([len_str | rest]) do
    len = String.to_integer(String.trim(len_str))
    parse_list_elements_db(rest, len, [])
  end

  defp parse_list_db([]), do: {:error, :unexpected_eof}

  defp parse_float([val_str | rest]) do
    case Float.parse(String.trim(val_str)) do
      {f, _} -> {:ok, Value.num(trunc(f)), rest}
      :error -> {:ok, Value.num(0), rest}
    end
  end

  defp parse_float([]), do: {:error, :unexpected_eof}

  defp parse_list_elements_db(lines, 0, acc), do: {:ok, Value.list(Enum.reverse(acc)), lines}

  defp parse_list_elements_db(lines, remaining, acc) do
    case parse_value(lines) do
      {:ok, val, rest} -> parse_list_elements_db(rest, remaining - 1, [val | acc])
      err -> err
    end
  end

  # Skip verb code sections
  defp parse_verb_code(lines, objects) do
    # Skip any non-verb-code lines until we find first verb reference
    lines = skip_to_verb_code(lines)
    parse_verb_code_loop(lines, objects)
  end

  # Skip lines until we find a verb code reference (#N:N)
  defp skip_to_verb_code([line | rest] = lines) do
    case Regex.match?(~r/^#\d+:\d+$/, String.trim(line)) do
      true -> lines
      false -> skip_to_verb_code(rest)
    end
  end

  defp skip_to_verb_code([]), do: []

  defp parse_verb_code_loop([], objects), do: {:ok, objects}

  defp parse_verb_code_loop(["#" <> ref | rest], objects) do
    case String.split(ref, ":") do
      [obj_id_str, verb_idx_str] ->
        process_verb_code_ref(obj_id_str, verb_idx_str, rest, objects)

      _ ->
        parse_verb_code_loop(rest, objects)
    end
  end

  defp parse_verb_code_loop([_line | rest], objects) do
    parse_verb_code_loop(rest, objects)
  end

  defp process_verb_code_ref(obj_id_str, verb_idx_str, rest, objects) do
    case {Integer.parse(obj_id_str), Integer.parse(verb_idx_str)} do
      {{obj_id, _}, {verb_idx, _}} ->
        with {:ok, code, rest} <- parse_code_block(rest),
             {:ok, objects} <- update_verb_code(objects, obj_id, verb_idx, code) do
          parse_verb_code_loop(rest, objects)
        end

      _ ->
        parse_verb_code_loop(rest, objects)
    end
  end

  defp parse_code_block(lines) do
    parse_code_block_loop(lines, [])
  end

  defp parse_code_block_loop(["." | rest], acc) do
    {:ok, Enum.reverse(acc), rest}
  end

  defp parse_code_block_loop([line | rest], acc) do
    parse_code_block_loop(rest, [line | acc])
  end

  defp parse_code_block_loop([], acc) do
    {:ok, Enum.reverse(acc), []}
  end

  defp update_verb_code(objects, obj_id, verb_idx, code) do
    case Map.get(objects, obj_id) do
      nil ->
        # Object not found - skip silently
        {:ok, objects}

      object ->
        case Enum.at(object.verbs, verb_idx) do
          nil ->
            # Verb index out of range - skip silently
            {:ok, objects}

          verb ->
            updated_verb = %{verb | code: code}
            updated_verbs = List.replace_at(object.verbs, verb_idx, updated_verb)
            updated_object = %{object | verbs: updated_verbs}
            {:ok, Map.put(objects, obj_id, updated_object)}
        end
    end
  end

  # Helper functions
  defp parse_line([line | rest]), do: {:ok, line, rest}
  defp parse_line([]), do: {:error, :unexpected_eof}

  defp parse_flags_line([line | rest]) do
    # Flags can be empty line or integer
    case String.trim(line) do
      "" -> {:ok, 0, rest}
      str -> parse_integer_line([str | rest])
    end
  end

  defp parse_integer_line([line | rest]) do
    case parse_integer(line) do
      {:ok, num} -> {:ok, num, rest}
      error -> error
    end
  end

  defp parse_integer(str) do
    case Integer.parse(String.trim(str)) do
      {num, _} -> {:ok, num}
      :error -> {:error, {:invalid_integer, str}}
    end
  end
end
