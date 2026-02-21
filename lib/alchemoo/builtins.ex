defmodule Alchemoo.Builtins do
  @moduledoc """
  MOO built-in functions.

  Implements the standard LambdaMOO built-in functions.
  """
  require Logger

  alias Alchemoo.Connection.Handler
  alias Alchemoo.Connection.Supervisor, as: ConnSupervisor
  alias Alchemoo.Database.Server, as: DBServer
  alias Alchemoo.Value

  @doc """
  Call a built-in function by name with arguments.
  """
  def call(name, args) when is_binary(name) do
    call(String.to_atom(name), args)
  end

  # Type conversion
  def call(:typeof, args), do: typeof(args)
  def call(:tostr, args), do: tostr(args)
  def call(:toint, args), do: toint(args)
  def call(:toobj, args), do: toobj(args)
  def call(:toliteral, args), do: toliteral(args)

  # List operations
  def call(:length, args), do: length_fn(args)
  def call(:is_member, args), do: member?(args)
  def call(:listappend, args), do: listappend(args)
  def call(:listinsert, args), do: listinsert(args)
  def call(:listdelete, args), do: listdelete(args)
  def call(:listset, args), do: listset(args)
  def call(:setadd, args), do: setadd(args)
  def call(:setremove, args), do: setremove(args)
  def call(:sort, args), do: sort_fn(args)

  # Comparison
  def call(:equal, args), do: equal(args)

  # Math
  def call(:random, args), do: random_fn(args)
  def call(:min, args), do: min_fn(args)
  def call(:max, args), do: max_fn(args)
  def call(:abs, args), do: abs_fn(args)
  def call(:sqrt, args), do: sqrt_fn(args)
  def call(:sin, args), do: sin_fn(args)
  def call(:cos, args), do: cos_fn(args)

  # Time
  def call(:time, args), do: time_fn(args)
  def call(:ctime, args), do: ctime_fn(args)

  # Output/Communication
  def call(:notify, args), do: notify(args)
  def call(:connected_players, args), do: connected_players(args)
  def call(:connection_name, args), do: connection_name(args)

  # Context
  def call(:player, args), do: player_fn(args)
  def call(:caller, args), do: caller_fn(args)
  def call(:this, args), do: this_fn(args)

  # String operations
  def call(:index, args), do: index_fn(args)
  def call(:rindex, args), do: rindex_fn(args)
  def call(:strsub, args), do: strsub(args)
  def call(:strcmp, args), do: strcmp(args)
  def call(:explode, args), do: explode(args)
  def call(:substitute, args), do: substitute(args)
  def call(:match, args), do: match_fn(args)
  def call(:rmatch, args), do: rmatch_fn(args)
  def call(:decode_binary, args), do: decode_binary(args)
  def call(:encode_binary, args), do: encode_binary(args)

  # Object operations
  def call(:valid, args), do: valid(args)
  def call(:parent, args), do: parent_fn(args)
  def call(:children, args), do: children(args)
  def call(:max_object, args), do: max_object(args)

  # Property operations
  def call(:properties, args), do: properties(args)
  def call(:property_info, args), do: property_info(args)
  def call(:get_property, args), do: get_property(args)
  def call(:set_property, args), do: set_property(args)

  # Object management
  def call(:create, args), do: create(args)
  def call(:recycle, args), do: recycle(args)
  def call(:chparent, args), do: chparent(args)
  def call(:move, args), do: move(args)

  # Verb management
  def call(:verbs, args), do: verbs(args)
  def call(:verb_info, args), do: verb_info(args)
  def call(:set_verb_info, args), do: set_verb_info(args)
  def call(:verb_args, args), do: verb_args(args)
  def call(:set_verb_args, args), do: set_verb_args(args)
  def call(:verb_code, args), do: verb_code(args)
  def call(:add_verb, args), do: add_verb(args)
  def call(:delete_verb, args), do: delete_verb(args)
  def call(:set_verb_code, args), do: set_verb_code(args)

  # Property management
  def call(:add_property, args), do: add_property(args)
  def call(:delete_property, args), do: delete_property(args)
  def call(:set_property_info, args), do: set_property_info(args)
  def call(:is_clear_property, args), do: clear_property?(args)
  def call(:clear_property, args), do: clear_property(args)

  # Task management
  def call(:suspend, args), do: suspend_fn(args)

  # Server management
  def call(:server_version, args), do: server_version(args)
  def call(:server_log, args), do: server_log(args)
  def call(:shutdown, args), do: shutdown(args)

  # Default
  def call(_name, _args), do: {:err, :E_VERBNF}

  # typeof(value) - return type as integer
  defp typeof([val]) do
    type_num =
      case Value.typeof(val) do
        :num -> 0
        :obj -> 1
        :str -> 2
        :err -> 3
        :list -> 4
      end

    Value.num(type_num)
  end

  defp typeof(_), do: Value.err(:E_ARGS)

  # suspend(seconds) - suspend task
  defp suspend_fn([{:num, seconds}]) when seconds >= 0 do
    throw({:suspend, seconds})
  end

  defp suspend_fn(_), do: Value.err(:E_ARGS)

  # tostr(values...) - convert to string
  defp tostr(args) do
    str = Enum.map_join(args, &Value.to_literal/1)
    Value.str(str)
  end

  # toint(value) - convert to integer
  defp toint([{:num, n}]), do: Value.num(n)

  defp toint([{:str, s}]) do
    case Integer.parse(s) do
      {n, _} -> Value.num(n)
      :error -> Value.num(0)
    end
  end

  defp toint([{:obj, n}]), do: Value.num(n)
  defp toint([{:err, _}]), do: Value.num(0)
  defp toint(_), do: Value.err(:E_ARGS)

  # toobj(value) - convert to object
  defp toobj([{:num, n}]), do: Value.obj(n)
  defp toobj([{:obj, n}]), do: Value.obj(n)

  defp toobj([{:str, s}]) do
    case Integer.parse(s) do
      {n, _} -> Value.obj(n)
      :error -> Value.obj(0)
    end
  end

  defp toobj(_), do: Value.err(:E_ARGS)

  # toliteral(value) - convert to literal string
  defp toliteral([val]) do
    Value.str(Value.to_literal(val))
  end

  defp toliteral(_), do: Value.err(:E_ARGS)

  # length(str_or_list) - get length
  defp length_fn([val]) do
    Value.length(val)
  end

  defp length_fn(_), do: Value.err(:E_ARGS)

  # is_member(value, list) - check membership
  defp member?([val, {:list, items}]) do
    case Enum.any?(items, &Value.equal?(&1, val)) do
      true -> Value.num(1)
      false -> Value.num(0)
    end
  end

  defp member?(_), do: Value.err(:E_ARGS)

  # listappend(list, value [, index]) - append to list
  defp listappend([{:list, items}, val]) do
    Value.list(items ++ [val])
  end

  defp listappend([{:list, items}, val, {:num, idx}]) when idx > 0 do
    {before, after_list} = Enum.split(items, idx)
    Value.list(before ++ [val] ++ after_list)
  end

  defp listappend(_), do: Value.err(:E_ARGS)

  # listinsert(list, value [, index]) - insert into list
  defp listinsert([{:list, items}, val]) do
    Value.list([val | items])
  end

  defp listinsert([{:list, items}, val, {:num, idx}]) when idx > 0 do
    {before, after_list} = Enum.split(items, idx - 1)
    Value.list(before ++ [val] ++ after_list)
  end

  defp listinsert(_), do: Value.err(:E_ARGS)

  # listdelete(list, index) - delete from list
  defp listdelete([{:list, items}, {:num, idx}]) when idx > 0 and idx <= length(items) do
    Value.list(List.delete_at(items, idx - 1))
  end

  defp listdelete(_), do: Value.err(:E_ARGS)

  # listset(list, value, index) - set list element
  defp listset([{:list, items}, val, {:num, idx}]) when idx > 0 and idx <= length(items) do
    Value.list(List.replace_at(items, idx - 1, val))
  end

  defp listset(_), do: Value.err(:E_ARGS)

  # equal(val1, val2) - test equality
  defp equal([val1, val2]) do
    case Value.equal?(val1, val2) do
      true -> Value.num(1)
      false -> Value.num(0)
    end
  end

  defp equal(_), do: Value.err(:E_ARGS)

  # random([max]) - random number
  defp random_fn([]) do
    Value.num(:rand.uniform(1_000_000_000))
  end

  defp random_fn([{:num, max}]) when max > 0 do
    Value.num(:rand.uniform(max))
  end

  defp random_fn(_), do: Value.err(:E_ARGS)

  # min(numbers...) - minimum value
  defp min_fn(args) do
    nums = Enum.map(args, fn {:num, n} -> n end)
    Value.num(Enum.min(nums))
  rescue
    _ -> Value.err(:E_ARGS)
  end

  # max(numbers...) - maximum value
  defp max_fn(args) do
    nums = Enum.map(args, fn {:num, n} -> n end)
    Value.num(Enum.max(nums))
  rescue
    _ -> Value.err(:E_ARGS)
  end

  # abs(number) - absolute value
  defp abs_fn([{:num, n}]) do
    Value.num(abs(n))
  end

  defp abs_fn(_), do: Value.err(:E_ARGS)

  # sqrt(number) - square root
  defp sqrt_fn([{:num, n}]) when n >= 0 do
    Value.num(trunc(:math.sqrt(n)))
  end

  defp sqrt_fn(_), do: Value.err(:E_ARGS)

  # sin(number) - sine
  defp sin_fn([{:num, n}]) do
    Value.num(trunc(:math.sin(n) * 1000))
  end

  defp sin_fn(_), do: Value.err(:E_ARGS)

  # cos(number) - cosine
  defp cos_fn([{:num, n}]) do
    Value.num(trunc(:math.cos(n) * 1000))
  end

  defp cos_fn(_), do: Value.err(:E_ARGS)

  # time() - current unix timestamp
  defp time_fn([]) do
    Value.num(System.system_time(:second))
  end

  defp time_fn(_), do: Value.err(:E_ARGS)

  # ctime([time]) - format time as string
  defp ctime_fn([]) do
    ctime_fn([Value.num(System.system_time(:second))])
  end

  defp ctime_fn([{:num, timestamp}]) do
    dt = DateTime.from_unix!(timestamp)
    Value.str(Calendar.strftime(dt, "%a %b %d %H:%M:%S %Y"))
  end

  defp ctime_fn(_), do: Value.err(:E_ARGS)

  ## Output/Communication

  # notify(player, text) - send text to player
  defp notify([{:obj, player_id}, {:str, text}]) do
    # Find connection for this player and send text
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        Handler.send_output(handler_pid, text <> "\n")
        Value.num(1)

      {:error, _} ->
        # Player not connected, fail silently (MOO behavior)
        Value.num(0)
    end
  end

  defp notify(_), do: Value.err(:E_ARGS)

  defp find_player_connection(player_id) do
    # Get all connection handlers and find one for this player
    connections = ConnSupervisor.list_connections()

    Enum.find_value(connections, {:error, :not_found}, fn pid ->
      case Handler.info(pid) do
        %{player_id: ^player_id} -> {:ok, pid}
        _ -> nil
      end
    end)
  end

  # connected_players() - list of connected player objects
  defp connected_players([]) do
    connections = ConnSupervisor.list_connections()

    player_ids =
      Enum.flat_map(connections, fn pid ->
        case Handler.info(pid) do
          %{player_id: id, state: :logged_in} when id != nil -> [id]
          _ -> []
        end
      end)

    Value.list(Enum.map(player_ids, &Value.obj/1))
  end

  defp connected_players(_), do: Value.err(:E_ARGS)

  # connection_name(player) - get connection info
  defp connection_name([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, _handler_pid} ->
        # TODO: Get actual connection info (IP, hostname)
        Value.str("localhost")

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp connection_name(_), do: Value.err(:E_ARGS)

  ## Context

  # player() - get current player object
  defp player_fn([]) do
    case get_task_context(:player) do
      # Default to wizard if no context
      nil -> Value.obj(2)
      player_id -> Value.obj(player_id)
    end
  end

  defp player_fn(_), do: Value.err(:E_ARGS)

  # caller() - get calling object
  defp caller_fn([]) do
    case get_task_context(:caller) do
      # Default to wizard if no context
      nil -> Value.obj(2)
      caller_id -> Value.obj(caller_id)
    end
  end

  defp caller_fn(_), do: Value.err(:E_ARGS)

  # this() - get current object
  defp this_fn([]) do
    case get_task_context(:this) do
      # Default to wizard if no context
      nil -> Value.obj(2)
      this_id -> Value.obj(this_id)
    end
  end

  defp this_fn(_), do: Value.err(:E_ARGS)

  defp get_task_context(key) do
    case Process.get(:task_context) do
      nil -> nil
      context -> Map.get(context, key)
    end
  end

  ## String Operations

  # index(str, substr [, case_matters]) - find substring
  defp index_fn([{:str, str}, {:str, substr}]) do
    index_fn([{:str, str}, {:str, substr}, Value.num(0)])
  end

  defp index_fn([{:str, str}, {:str, substr}, {:num, case_matters}]) do
    {search_str, search_substr} =
      case case_matters do
        0 -> {String.downcase(str), String.downcase(substr)}
        _ -> {str, substr}
      end

    case :binary.match(search_str, search_substr) do
      {pos, _len} ->
        # Calculate grapheme index from byte offset
        prefix = :binary.part(search_str, 0, pos)
        grapheme_pos = String.length(prefix)
        # 1-based indexing
        Value.num(grapheme_pos + 1)

      :nomatch ->
        Value.num(0)
    end
  end

  defp index_fn(_), do: Value.err(:E_ARGS)

  # rindex(str, substr [, case_matters]) - find substring from end
  defp rindex_fn([{:str, str}, {:str, substr}]) do
    rindex_fn([{:str, str}, {:str, substr}, Value.num(0)])
  end

  defp rindex_fn([{:str, str}, {:str, substr}, {:num, case_matters}]) do
    {search_str, search_substr} =
      case case_matters do
        0 -> {String.downcase(str), String.downcase(substr)}
        _ -> {str, substr}
      end

    # Use :binary.matches to find all and take the last one
    case :binary.matches(search_str, search_substr) do
      [] ->
        Value.num(0)

      matches ->
        {pos, _len} = List.last(matches)
        # Calculate grapheme index from byte offset
        prefix = :binary.part(search_str, 0, pos)
        grapheme_pos = String.length(prefix)
        Value.num(grapheme_pos + 1)
    end
  end

  defp rindex_fn(_), do: Value.err(:E_ARGS)

  # strsub(str, old, new [, case_matters]) - replace substring
  defp strsub([{:str, str}, {:str, old}, {:str, new}]) do
    strsub([{:str, str}, {:str, old}, {:str, new}, Value.num(0)])
  end

  defp strsub([{:str, str}, {:str, old}, {:str, new}, {:num, case_matters}]) do
    result =
      case case_matters do
        0 ->
          # Case-insensitive replace
          regex = Regex.compile!(Regex.escape(old), "i")
          Regex.replace(regex, str, new, global: false)

        _ ->
          String.replace(str, old, new, global: false)
      end

    Value.str(result)
  end

  defp strsub(_), do: Value.err(:E_ARGS)

  # strcmp(str1, str2) - compare strings
  defp strcmp([{:str, str1}, {:str, str2}]) do
    cond do
      str1 < str2 -> Value.num(-1)
      str1 > str2 -> Value.num(1)
      true -> Value.num(0)
    end
  end

  defp strcmp(_), do: Value.err(:E_ARGS)

  # explode(str [, delim]) - split string
  defp explode([{:str, str}]) do
    explode([{:str, str}, Value.str(" ")])
  end

  defp explode([{:str, str}, {:str, delim}]) do
    parts = String.split(str, delim)
    Value.list(Enum.map(parts, &Value.str/1))
  end

  defp explode(_), do: Value.err(:E_ARGS)

  # substitute(template, subs) - string substitution
  defp substitute([{:str, template}, {:list, subs}]) do
    case subs do
      [{:num, start_pos}, {:num, _end_pos}, {:list, captures}, {:str, matched_str}] ->
        # Perform substitution
        result = do_substitute(template, start_pos, matched_str, captures)
        Value.str(result)

      _ ->
        Value.err(:E_INVARG)
    end
  end

  defp substitute(_), do: Value.err(:E_ARGS)

  defp do_substitute(template, start_pos, matched_str, captures) do
    Regex.replace(~r/%([0-9%])/, template, fn _, char ->
      case char do
        "%" -> "%"
        "0" -> matched_str
        digit -> get_capture(digit, start_pos, matched_str, captures)
      end
    end)
  end

  defp get_capture(digit, start_pos, matched_str, captures) do
    idx = String.to_integer(digit) - 1

    case Enum.at(captures, idx) do
      {:list, [{:num, c_start}, {:num, c_end}]} when c_start > 0 ->
        rel_start = c_start - start_pos
        rel_len = c_end - c_start + 1
        extract_slice(matched_str, rel_start, rel_len)

      _ ->
        ""
    end
  end

  defp extract_slice(str, start, len) when start >= 0 and len > 0 do
    String.slice(str, start, len)
  end

  defp extract_slice(_str, _start, _len), do: ""

  ## Object Operations

  # valid(obj) - check if object exists
  defp valid([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, _} -> Value.num(1)
      {:error, _} -> Value.num(0)
    end
  end

  defp valid(_), do: Value.err(:E_ARGS)

  # parent(obj) - get parent object
  defp parent_fn([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} -> Value.obj(obj.parent)
      {:error, err} -> Value.err(err)
    end
  end

  defp parent_fn(_), do: Value.err(:E_ARGS)

  # children(obj) - get child objects
  defp children([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        # Collect all children by traversing sibling chain
        children = collect_children(obj.child)
        Value.list(Enum.map(children, &Value.obj/1))

      {:error, err} ->
        Value.err(err)
    end
  end

  defp children(_), do: Value.err(:E_ARGS)

  defp collect_children(-1), do: []

  defp collect_children(child_id) do
    case DBServer.get_object(child_id) do
      {:ok, child} -> [child_id | collect_children(child.sibling)]
      {:error, _} -> []
    end
  end

  # max_object() - get highest object number ever created
  defp max_object([]) do
    stats = DBServer.stats()
    Value.num(stats.max_object)
  end

  defp max_object(_), do: Value.err(:E_ARGS)

  ## Property Operations

  # properties(obj) - list property names
  defp properties([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        prop_names = Enum.map(obj.properties, fn prop -> Value.str(prop.name) end)
        Value.list(prop_names)

      {:error, err} ->
        Value.err(err)
    end
  end

  defp properties(_), do: Value.err(:E_ARGS)

  # property_info(obj, prop) - get property info
  defp property_info([{:obj, obj_id}, {:str, prop_name}]) do
    case DBServer.get_property_info(obj_id, prop_name) do
      {:ok, {owner, perms}} ->
        Value.list([Value.obj(owner), Value.str(perms)])

      {:error, err} ->
        Value.err(err)
    end
  end

  defp property_info(_), do: Value.err(:E_ARGS)

  # set_property_info(obj, prop, info) - set property info
  defp set_property_info([{:obj, obj_id}, {:str, prop_name}, {:list, info}]) do
    owner =
      case Enum.at(info, 0) do
        {:obj, id} -> id
        _ -> obj_id
      end

    perms =
      case Enum.at(info, 1) do
        {:str, p} -> p
        _ -> ""
      end

    case DBServer.set_property_info(obj_id, prop_name, {owner, perms}) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp set_property_info(_), do: Value.err(:E_ARGS)

  # is_clear_property(obj, prop) - check if property is clear
  defp clear_property?([{:obj, obj_id}, {:str, prop_name}]) do
    case DBServer.is_clear_property?(obj_id, prop_name) do
      {:ok, result} ->
        case result do
          true -> Value.num(1)
          false -> Value.num(0)
        end

      {:error, err} ->
        Value.err(err)
    end
  end

  defp clear_property?(_), do: Value.err(:E_ARGS)

  ## Property Access

  # get_property(obj, prop) - get property value
  defp get_property([{:obj, obj_id}, {:str, prop_name}]) do
    case DBServer.get_property(obj_id, prop_name) do
      {:ok, value} -> value
      {:error, err} -> Value.err(err)
    end
  end

  defp get_property(_), do: Value.err(:E_ARGS)

  # set_property(obj, prop, value) - set property value
  defp set_property([{:obj, obj_id}, {:str, prop_name}, value]) do
    case DBServer.set_property(obj_id, prop_name, value) do
      :ok -> value
      {:error, err} -> Value.err(err)
    end
  end

  defp set_property(_), do: Value.err(:E_ARGS)

  ## List Operations (Set)

  # setadd(list, value) - add value to list if not present (set semantics)
  defp setadd([{:list, items}, value]) do
    case Enum.any?(items, fn item -> Value.equal?(item, value) end) do
      true ->
        Value.list(items)

      false ->
        Value.list(items ++ [value])
    end
  end

  defp setadd(_), do: Value.err(:E_ARGS)

  # setremove(list, value) - remove value from list (set semantics)
  defp setremove([{:list, items}, value]) do
    new_items = Enum.reject(items, fn item -> Value.equal?(item, value) end)
    Value.list(new_items)
  end

  defp setremove(_), do: Value.err(:E_ARGS)

  ## Object Management

  # create(parent) - create new object
  defp create([{:obj, parent_id}]) do
    case DBServer.create_object(parent_id) do
      {:ok, new_id} -> Value.obj(new_id)
      {:error, err} -> Value.err(err)
    end
  end

  defp create(_), do: Value.err(:E_ARGS)

  # recycle(obj) - delete object
  defp recycle([{:obj, obj_id}]) do
    case DBServer.recycle_object(obj_id) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp recycle(_), do: Value.err(:E_ARGS)

  # chparent(obj, parent) - change parent
  defp chparent([{:obj, obj_id}, {:obj, parent_id}]) do
    case DBServer.change_parent(obj_id, parent_id) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp chparent(_), do: Value.err(:E_ARGS)

  # move(obj, dest) - move object to new location
  defp move([{:obj, obj_id}, {:obj, dest_id}]) do
    case DBServer.move_object(obj_id, dest_id) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp move(_), do: Value.err(:E_ARGS)

  ## Verb Management

  # verbs(obj) - list verbs on object
  defp verbs([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        verb_names = Enum.map(obj.verbs, fn v -> Value.str(v.name) end)
        Value.list(verb_names)

      {:error, err} ->
        Value.err(err)
    end
  end

  defp verbs(_), do: Value.err(:E_ARGS)

  # verb_info(obj, verb) - get verb info
  defp verb_info([{:obj, obj_id}, {:str, verb_name}]) do
    case DBServer.get_verb_info(obj_id, verb_name) do
      {:ok, {owner, perms, name}} ->
        Value.list([Value.obj(owner), Value.str(Integer.to_string(perms)), Value.str(name)])

      {:error, err} ->
        Value.err(err)
    end
  end

  defp verb_info(_), do: Value.err(:E_ARGS)

  # set_verb_info(obj, verb, info) - set verb info
  defp set_verb_info([{:obj, obj_id}, {:str, verb_name}, {:list, info}]) do
    {owner, perms, name} = extract_verb_info(info, obj_id, verb_name)

    case DBServer.set_verb_info(obj_id, verb_name, {owner, perms, name}) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp set_verb_info(_), do: Value.err(:E_ARGS)

  defp extract_verb_info(info, default_owner, default_name) do
    owner =
      case Enum.at(info, 0) do
        {:obj, id} -> id
        _ -> default_owner
      end

    perms =
      case Enum.at(info, 1) do
        {:str, p} -> parse_perms(p)
        {:num, p} -> p
        _ -> 173
      end

    name =
      case Enum.at(info, 2) do
        {:str, n} -> n
        _ -> default_name
      end

    {owner, perms, name}
  end

  defp parse_perms(p) do
    case Integer.parse(p) do
      {n, _} -> n
      :error -> 173
    end
  end

  # verb_args(obj, verb) - get verb args
  defp verb_args([{:obj, obj_id}, {:str, verb_name}]) do
    case DBServer.get_verb_args(obj_id, verb_name) do
      {:ok, {dobj, prep, iobj}} ->
        Value.list([
          Value.str(Atom.to_string(dobj)),
          Value.str(Atom.to_string(prep)),
          Value.str(Atom.to_string(iobj))
        ])

      {:error, err} ->
        Value.err(err)
    end
  end

  defp verb_args(_), do: Value.err(:E_ARGS)

  # set_verb_args(obj, verb, args) - set verb args
  defp set_verb_args([{:obj, obj_id}, {:str, verb_name}, {:list, args}]) do
    dobj =
      case Enum.at(args, 0) do
        {:str, s} -> String.to_atom(s)
        _ -> :none
      end

    prep =
      case Enum.at(args, 1) do
        {:str, s} -> String.to_atom(s)
        _ -> :none
      end

    iobj =
      case Enum.at(args, 2) do
        {:str, s} -> String.to_atom(s)
        _ -> :none
      end

    case DBServer.set_verb_args(obj_id, verb_name, {dobj, prep, iobj}) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp set_verb_args(_), do: Value.err(:E_ARGS)

  # verb_code(obj, verb) - get verb code
  defp verb_code([{:obj, obj_id}, {:str, verb_name}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} -> get_verb_code_from_object(obj, verb_name)
      {:error, err} -> Value.err(err)
    end
  end

  defp verb_code(_), do: Value.err(:E_ARGS)

  defp get_verb_code_from_object(obj, verb_name) do
    case Enum.find(obj.verbs, fn v -> v.name == verb_name end) do
      nil ->
        Value.err(:E_VERBNF)

      verb ->
        # Return list of code lines
        lines = Enum.map(verb.code, &Value.str/1)
        Value.list(lines)
    end
  end

  # add_verb(obj, info, code) - add verb
  defp add_verb([{:obj, obj_id}, {:list, info}, {:list, code}]) do
    # Extract info: {owner, perms, name}
    owner =
      case Enum.at(info, 0) do
        {:obj, id} -> id
        _ -> obj_id
      end

    perms =
      case Enum.at(info, 1) do
        {:str, p} -> p
        _ -> "rx"
      end

    name =
      case Enum.at(info, 2) do
        {:str, n} -> n
        _ -> "verb"
      end

    # Convert code lines to strings
    code_lines =
      Enum.map(code, fn
        {:str, line} -> line
        _ -> ""
      end)

    case DBServer.add_verb(obj_id, name, owner, perms, code_lines) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp add_verb(_), do: Value.err(:E_ARGS)

  # delete_verb(obj, verb) - delete verb
  defp delete_verb([{:obj, obj_id}, {:str, verb_name}]) do
    case DBServer.delete_verb(obj_id, verb_name) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp delete_verb(_), do: Value.err(:E_ARGS)

  # set_verb_code(obj, verb, code) - set verb code
  defp set_verb_code([{:obj, obj_id}, {:str, verb_name}, {:list, code}]) do
    # Convert code lines to strings
    code_lines =
      Enum.map(code, fn
        {:str, line} -> line
        _ -> ""
      end)

    case DBServer.set_verb_code(obj_id, verb_name, code_lines) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp set_verb_code(_), do: Value.err(:E_ARGS)

  ## Property Management

  # add_property(obj, name, value, info) - add property
  defp add_property([{:obj, obj_id}, {:str, name}, value, {:list, info}]) do
    # Extract info: {owner, perms}
    owner =
      case Enum.at(info, 0) do
        {:obj, id} -> id
        _ -> obj_id
      end

    perms =
      case Enum.at(info, 1) do
        {:str, p} -> p
        _ -> "r"
      end

    case DBServer.add_property(obj_id, name, value, owner, perms) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp add_property(_), do: Value.err(:E_ARGS)

  # delete_property(obj, name) - delete property
  defp delete_property([{:obj, obj_id}, {:str, name}]) do
    case DBServer.delete_property(obj_id, name) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp delete_property(_), do: Value.err(:E_ARGS)

  # clear_property(obj, name) - clear property to default
  defp clear_property([{:obj, obj_id}, {:str, name}]) do
    case DBServer.set_property(obj_id, name, :clear) do
      {:ok, _} -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp clear_property(_), do: Value.err(:E_ARGS)

  ## String Operations

  # match(str, pattern [, case_matters]) - pattern matching
  defp match_fn([{:str, str}, {:str, pattern}]) do
    match_fn([{:str, str}, {:str, pattern}, Value.num(0)])
  end

  defp match_fn([{:str, str}, {:str, pattern}, {:num, case_matters}]) do
    pcre_pattern = moo_to_pcre(pattern)

    opts =
      case case_matters do
        0 -> [:caseless]
        _ -> []
      end

    case Regex.compile(pcre_pattern, opts) do
      {:ok, regex} ->
        case Regex.run(regex, str, return: :index) do
          nil ->
            Value.list([])

          [full_match | captures] ->
            {start, len} = full_match
            # MOO uses 1-based indexing
            moo_start = start + 1
            moo_end = start + len + 1

            # Matched string
            matched_str = String.slice(str, start, len)

            # Format captures: list of 9 pairs {start, end}
            # Unmatched captures are {0, -1}
            moo_captures = format_moo_captures(captures, 9)

            Value.list([
              Value.num(moo_start),
              Value.num(moo_end),
              Value.list(moo_captures),
              Value.str(matched_str)
            ])
        end

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp match_fn(_), do: Value.err(:E_ARGS)

  # rmatch(str, pattern [, case_matters]) - reverse pattern matching
  defp rmatch_fn([{:str, str}, {:str, pattern}]) do
    rmatch_fn([{:str, str}, {:str, pattern}, Value.num(0)])
  end

  defp rmatch_fn([{:str, str}, {:str, pattern}, {:num, case_matters}]) do
    # For rmatch, we want the rightmost match.
    # PCRE doesn't support this directly, so we find all and take the last.
    pcre_pattern = moo_to_pcre(pattern)

    opts =
      case case_matters do
        0 -> [:caseless]
        _ -> []
      end

    case Regex.compile(pcre_pattern, opts) do
      {:ok, regex} ->
        case Regex.scan(regex, str, return: :index) do
          [] ->
            Value.list([])

          matches ->
            # matches is a list of [full_match | captures]
            [full_match | captures] = List.last(matches)
            {start, len} = full_match
            moo_start = start + 1
            moo_end = start + len + 1
            matched_str = String.slice(str, start, len)
            moo_captures = format_moo_captures(captures, 9)

            Value.list([
              Value.num(moo_start),
              Value.num(moo_end),
              Value.list(moo_captures),
              Value.str(matched_str)
            ])
        end

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp rmatch_fn(_), do: Value.err(:E_ARGS)

  # Helper: Convert MOO regex to PCRE
  defp moo_to_pcre(moo_pattern) do
    # Escape PCRE specials: . * + ? [ ] ( ) { } ^ $ \ |
    # But MOO has its own specials.

    # 1. Escape all PCRE specials that are NOT MOO specials (mostly just \ and brackets/parens)
    # Actually, it's easier to escape EVERYTHING and then unescape the MOO specials.
    # Wait, PCRE specials that are MOO specials: . * + ? ^ $ [ ]
    # PCRE specials that are NOT MOO specials: ( ) { } \ |
    # MOO uses % for escaping and grouping.

    # Let's do a manual scan
    moo_pattern
    |> String.graphemes()
    |> do_moo_to_pcre([])
    |> Enum.reverse()
    |> Enum.join()
  end

  defp do_moo_to_pcre([], acc), do: acc

  # MOO special: % followed by something
  defp do_moo_to_pcre(["%", char | rest], acc) do
    do_moo_to_pcre(rest, [handle_percent_escape(char) | acc])
  end

  # MOO special characters (unguarded)
  defp do_moo_to_pcre([char | rest], acc) when char in ~w(. * + ? ^ $ [ ]) do
    do_moo_to_pcre(rest, [char | acc])
  end

  # PCRE special characters that are NOT MOO specials (must be escaped)
  defp do_moo_to_pcre([char | rest], acc) when char in ~w[\ ( ) { } |] do
    do_moo_to_pcre(rest, ["\\#{char}" | acc])
  end

  # Normal characters
  defp do_moo_to_pcre([char | rest], acc) do
    do_moo_to_pcre(rest, [char | acc])
  end

  defp handle_percent_escape("("), do: "("
  defp handle_percent_escape(")"), do: ")"
  defp handle_percent_escape("|"), do: "|"
  defp handle_percent_escape("."), do: "\\."
  defp handle_percent_escape("*"), do: "\\*"
  defp handle_percent_escape("+"), do: "\\+"
  defp handle_percent_escape("?"), do: "\\?"
  defp handle_percent_escape("["), do: "\\["
  defp handle_percent_escape("]"), do: "\\]"
  defp handle_percent_escape("^"), do: "\\^"
  defp handle_percent_escape("$"), do: "\\$"
  defp handle_percent_escape("%"), do: "%"
  defp handle_percent_escape("w"), do: "\\w"
  defp handle_percent_escape("W"), do: "\\W"
  defp handle_percent_escape("b"), do: "\\b"
  defp handle_percent_escape("<"), do: "\\b"
  defp handle_percent_escape(">"), do: "\\b"

  defp handle_percent_escape(digit) when digit in ~w(1 2 3 4 5 6 7 8 9),
    do: "\\#{digit}"

  defp handle_percent_escape(char), do: "\\#{char}"

  # Helper: format captures for MOO
  defp format_moo_captures(indices, count) do
    # Convert [{start, len}, ...] to [{start+1, start+len}, ...]
    moo_indices =
      Enum.map(indices, fn
        {-1, _} -> Value.list([Value.num(0), Value.num(-1)])
        {start, len} -> Value.list([Value.num(start + 1), Value.num(start + len)])
      end)

    # Pad to 'count' captures
    padding =
      case length(moo_indices) < count do
        true ->
          List.duplicate(Value.list([Value.num(0), Value.num(-1)]), count - length(moo_indices))

        false ->
          []
      end

    moo_indices ++ padding
  end

  # decode_binary(str) - decode binary string
  defp decode_binary([{:str, str}]) do
    # Simple for now - just return the string
    Value.str(str)
  end

  defp decode_binary(_), do: Value.err(:E_ARGS)

  # encode_binary(str) - encode to binary string
  defp encode_binary([{:str, str}]) do
    # Simple for now - just return the string
    Value.str(str)
  end

  defp encode_binary(_), do: Value.err(:E_ARGS)

  ## List Operations

  # sort(list) - sort list
  defp sort_fn([{:list, items}]) do
    sorted =
      Enum.sort(items, fn a, b ->
        compare_values(a, b) <= 0
      end)

    Value.list(sorted)
  end

  defp sort_fn(_), do: Value.err(:E_ARGS)

  # Helper: compare MOO values for sorting
  defp compare_values({:num, a}, {:num, b}), do: a - b

  defp compare_values({:str, a}, {:str, b}) do
    cond do
      a < b -> -1
      a > b -> 1
      true -> 0
    end
  end

  defp compare_values({:obj, a}, {:obj, b}), do: a - b

  defp compare_values({type_a, _}, {type_b, _}) do
    # Sort by type: num < obj < str < err < list
    type_order = %{num: 0, obj: 1, str: 2, err: 3, list: 4}
    Map.get(type_order, type_a, 5) - Map.get(type_order, type_b, 5)
  end

  ## Server Management

  # server_version() - get server version string
  defp server_version([]) do
    Value.str("Alchemoo #{Alchemoo.Version.version()}")
  end

  defp server_version(_), do: Value.err(:E_ARGS)

  # server_log(message) - log message to server log
  defp server_log([{:str, message}]) do
    Logger.info("MOO: #{message}")
    Value.num(1)
  end

  defp server_log(_), do: Value.err(:E_ARGS)

  # shutdown([message]) - shutdown server
  defp shutdown([]) do
    shutdown([Value.str("Shutdown by MOO task")])
  end

  defp shutdown([{:str, message}]) do
    Logger.warning("Server shutdown triggered by MOO task: #{message}")
    # Trigger application stop after a delay
    spawn(fn ->
      Process.sleep(1000)
      System.stop(0)
    end)

    Value.num(1)
  end

  defp shutdown(_), do: Value.err(:E_ARGS)
end
