defmodule Alchemoo.Builtins do
  @moduledoc """
  MOO built-in functions.

  Implements the standard LambdaMOO built-in functions.
  """
  require Logger
  import Bitwise

  alias Alchemoo.Connection.Handler
  alias Alchemoo.Connection.Supervisor, as: ConnSupervisor
  alias Alchemoo.Database.Flags
  alias Alchemoo.Database.Server, as: DBServer
  alias Alchemoo.Value

  @doc """
  Call a built-in function by name with arguments.
  """
  def call(name, args) when is_binary(name) do
    call(String.to_atom(name), args, %{})
  end

  def call(name, args) when is_atom(name) do
    call(name, args, %{})
  end

  @doc """
  Call a built-in function by name with arguments and environment.
  """
  def call(name, args, env) when is_binary(name) do
    call(String.to_atom(name), args, env)
  end

  # Type conversion
  def call(:typeof, args, _env), do: typeof(args)
  def call(:tostr, args, _env), do: tostr(args)
  def call(:toint, args, _env), do: toint(args)
  def call(:tonum, args, _env), do: toint(args)
  def call(:toobj, args, _env), do: toobj(args)
  def call(:toliteral, args, _env), do: toliteral(args)

  # List operations
  def call(:length, args, _env), do: length_fn(args)
  def call(:is_member, args, _env), do: member?(args)
  def call(:listappend, args, _env), do: listappend(args)
  def call(:listinsert, args, _env), do: listinsert(args)
  def call(:listdelete, args, _env), do: listdelete(args)
  def call(:listset, args, _env), do: listset(args)
  def call(:setadd, args, _env), do: setadd(args)
  def call(:setremove, args, _env), do: setremove(args)
  def call(:sort, args, _env), do: sort_fn(args)
  def call(:reverse, args, _env), do: reverse_fn(args)

  # Comparison
  def call(:equal, args, _env), do: equal(args)

  # Math
  def call(:random, args, _env), do: random_fn(args)
  def call(:min, args, _env), do: min_fn(args)
  def call(:max, args, _env), do: max_fn(args)
  def call(:abs, args, _env), do: abs_fn(args)
  def call(:sqrt, args, _env), do: sqrt_fn(args)
  def call(:sin, args, _env), do: sin_fn(args)
  def call(:cos, args, _env), do: cos_fn(args)
  def call(:tan, args, _env), do: tan_fn(args)
  def call(:sinh, args, _env), do: sinh_fn(args)
  def call(:cosh, args, _env), do: cosh_fn(args)
  def call(:tanh, args, _env), do: tanh_fn(args)
  def call(:asin, args, _env), do: asin_fn(args)
  def call(:acos, args, _env), do: acos_fn(args)
  def call(:atan, args, _env), do: atan_fn(args)
  def call(:atan2, args, _env), do: atan2_fn(args)
  def call(:exp, args, _env), do: exp_fn(args)
  def call(:log, args, _env), do: log_fn(args)
  def call(:log10, args, _env), do: log10_fn(args)
  def call(:ceil, args, _env), do: ceil_fn(args)
  def call(:floor, args, _env), do: floor_fn(args)
  def call(:trunc, args, _env), do: trunc_fn(args)
  def call(:floatstr, args, _env), do: floatstr(args)

  # Time
  def call(:time, args, _env), do: time_fn(args)
  def call(:ctime, args, _env), do: ctime_fn(args)

  # Output/Communication
  def call(:notify, args, _env), do: notify(args)
  def call(:notify_except, args, _env), do: notify_except_fn(args)
  def call(:connected_players, args, _env), do: connected_players(args)
  def call(:connection_name, args, _env), do: connection_name(args)
  def call(:boot_player, args, _env), do: boot_player(args)
  def call(:flush_input, args, _env), do: flush_input_fn(args)
  def call(:read, args, _env), do: read_fn(args)
  def call(:connection_options, args, _env), do: connection_options(args)
  def call(:connection_option, args, _env), do: connection_option(args)
  def call(:set_connection_option, args, _env), do: set_connection_option(args)
  def call(:output_delimiters, args, _env), do: output_delimiters(args)
  def call(:set_output_delimiters, args, _env), do: set_output_delimiters(args)

  # Context
  def call(:player, args, _env), do: player_fn(args)
  def call(:caller, args, _env), do: caller_fn(args)
  def call(:this, args, _env), do: this_fn(args)
  def call(:is_player, args, _env), do: player?(args)
  def call(:is_wizard, args, _env), do: wizard?(args)
  def call(:players, args, _env), do: players_fn(args)
  def call(:set_player_flag, args, _env), do: set_player_flag(args)
  def call(:check_password, args, _env), do: check_password_fn(args)

  # String operations
  def call(:index, args, _env), do: index_fn(args)
  def call(:rindex, args, _env), do: rindex_fn(args)
  def call(:strsub, args, _env), do: strsub(args)
  def call(:strcmp, args, _env), do: strcmp(args)
  def call(:explode, args, _env), do: explode(args)
  def call(:substitute, args, _env), do: substitute(args)
  def call(:match, args, _env), do: match_fn(args)
  def call(:rmatch, args, _env), do: rmatch_fn(args)
  def call(:decode_binary, args, _env), do: decode_binary(args)
  def call(:encode_binary, args, _env), do: encode_binary(args)
  def call(:crypt, args, _env), do: crypt(args)
  def call(:binary_hash, args, _env), do: binary_hash(args)
  def call(:value_hash, args, _env), do: value_hash_fn(args)

  # Object operations
  def call(:valid, args, _env), do: valid(args)
  def call(:parent, args, _env), do: parent_fn(args)
  def call(:children, args, _env), do: children(args)
  def call(:max_object, args, _env), do: max_object(args)
  def call(:chown, args, _env), do: chown(args)
  def call(:renumber, args, _env), do: renumber(args)
  def call(:reset_max_object, args, _env), do: reset_max_object(args)
  def call(:match_object, args, env), do: match_object_fn(args, env)

  # Property operations
  def call(:properties, args, _env), do: properties(args)
  def call(:property_info, args, _env), do: property_info(args)
  def call(:get_property, args, _env), do: get_property(args)
  def call(:set_property, args, _env), do: set_property(args)

  # Object management
  def call(:create, args, _env), do: create(args)
  def call(:recycle, args, _env), do: recycle(args)
  def call(:chparent, args, _env), do: chparent(args)
  def call(:move, args, _env), do: move(args)

  # Verb management
  def call(:verbs, args, _env), do: verbs(args)
  def call(:verb_info, args, _env), do: verb_info(args)
  def call(:set_verb_info, args, _env), do: set_verb_info(args)
  def call(:verb_args, args, _env), do: verb_args(args)
  def call(:set_verb_args, args, _env), do: set_verb_args(args)
  def call(:verb_code, args, _env), do: verb_code(args)
  def call(:add_verb, args, _env), do: add_verb(args)
  def call(:delete_verb, args, _env), do: delete_verb(args)
  def call(:set_verb_code, args, _env), do: set_verb_code(args)
  def call(:function_info, args, _env), do: function_info(args)
  def call(:disassemble, args, _env), do: disassemble(args)

  # Property management
  def call(:add_property, args, _env), do: add_property(args)
  def call(:delete_property, args, _env), do: delete_property(args)
  def call(:set_property_info, args, _env), do: set_property_info(args)
  def call(:is_clear_property, args, _env), do: clear_property?(args)
  def call(:clear_property, args, _env), do: clear_property(args)

  # Task management
  def call(:suspend, args, _env), do: suspend_fn(args)
  def call(:yield, args, _env), do: yield_fn(args)
  def call(:task_id, args, _env), do: task_id(args)
  def call(:queued_tasks, args, _env), do: queued_tasks(args)
  def call(:kill_task, args, _env), do: kill_task(args)
  def call(:resume, args, _env), do: resume_fn(args)
  def call(:task_stack, args, _env), do: task_stack(args)
  def call(:queue_info, args, _env), do: queue_info(args)
  def call(:raise, args, _env), do: raise_fn(args)
  def call(:call_function, args, env), do: call_function(args, env)
  def call(:eval, args, _env), do: eval_fn(args)
  def call(:pass, args, env), do: pass_fn(args, env)

  # Security
  def call(:caller_perms, args, _env), do: caller_perms(args)
  def call(:set_task_perms, args, _env), do: set_task_perms(args)
  def call(:callers, args, _env), do: callers_fn(args)

  # Network
  def call(:idle_seconds, args, _env), do: idle_seconds(args)
  def call(:connected_seconds, args, _env), do: connected_seconds(args)
  def call(:buffered_output_length, args, _env), do: buffered_output_length(args)
  def call(:listen, args, _env), do: listen(args)
  def call(:unlisten, args, _env), do: unlisten(args)
  def call(:open_network_connection, args, _env), do: open_network_connection(args)

  # Server management
  def call(:server_version, args, _env), do: server_version(args)
  def call(:server_log, args, _env), do: server_log(args)
  def call(:shutdown, args, _env), do: shutdown(args)
  def call(:memory_usage, args, _env), do: memory_usage(args)
  def call(:db_disk_size, args, _env), do: db_disk_size(args)
  def call(:dump_database, args, _env), do: dump_database(args)
  def call(:server_started, args, _env), do: server_started(args)

  # Utilities
  def call(:force_input, args, _env), do: force_input(args)
  def call(:read_binary, args, _env), do: read_binary(args)
  def call(:object_bytes, args, _env), do: object_bytes(args)
  def call(:value_bytes, args, _env), do: value_bytes(args)
  def call(:ticks_left, args, _env), do: ticks_left(args)
  def call(:seconds_left, args, _env), do: seconds_left(args)

  # Default
  def call(_name, _args, _env), do: {:err, :E_VERBNF}

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
    wait_in_task(seconds * 1000)
  end

  defp suspend_fn(_), do: Value.err(:E_ARGS)

  # resume(task_id [, value]) - resume suspended task
  defp resume_fn([{:num, target_id}]) do
    resume_fn([Value.num(target_id), Value.num(0)])
  end

  defp resume_fn([{:num, target_id}, value]) do
    tasks = Alchemoo.Task.list_tasks()
    found = Enum.find(tasks, fn {id, _pid, _meta} -> :erlang.phash2(id) == target_id end)

    case found do
      {_id, pid, _meta} ->
        send(pid, {:resume, value})
        Value.num(0)

      nil ->
        Value.err(:E_INVARG)
    end
  end

  defp resume_fn(_), do: Value.err(:E_ARGS)

  # yield() - yield execution
  defp yield_fn([]) do
    suspend_fn([Value.num(0)])
  end

  defp yield_fn(_), do: Value.err(:E_ARGS)

  # read([player]) - read line of input from player
  defp read_fn([]) do
    player_id = get_task_context(:player) || 2
    read_fn([Value.obj(player_id)])
  end

  defp read_fn([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        # Signal handler we are waiting
        Handler.request_input(handler_pid, self())

        # Wait for input while still handling GenServer calls
        wait_for_input_or_call()

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp read_fn(_), do: Value.err(:E_ARGS)

  defp wait_in_task(0), do: :ok

  defp wait_in_task(timeout_ms) do
    start_time = System.monotonic_time(:millisecond)

    receive do
      {:"$gen_call", from, :get_context} ->
        context = Process.get(:task_context)
        GenServer.reply(from, context)
        elapsed = System.monotonic_time(:millisecond) - start_time
        remaining = max(0, timeout_ms - elapsed)
        wait_in_task(remaining)
    after
      timeout_ms ->
        :ok
    end
  end

  defp wait_for_input_or_call do
    receive do
      {:input_received, line} ->
        Value.str(line)

      {:"$gen_call", from, :get_context} ->
        context = Process.get(:task_context)
        GenServer.reply(from, context)
        wait_for_input_or_call()
    after
      300_000 ->
        # 5 minute timeout
        Value.err(:E_PERM)
    end
  end

  # task_id() - get current task ID (integer)
  defp task_id([]) do
    case get_task_context(:id) do
      nil ->
        Value.num(0)

      id when is_reference(id) ->
        # Convert reference to integer for MOO
        Value.num(:erlang.phash2(id))

      id when is_integer(id) ->
        Value.num(id)
    end
  end

  defp task_id(_), do: Value.err(:E_ARGS)

  # queued_tasks() - list all queued/suspended tasks
  defp queued_tasks([]) do
    tasks = Alchemoo.Task.list_tasks()
    # MOO expects a list of task IDs
    # Our list_tasks returns [{id, pid, metadata}]
    ids =
      Enum.map(tasks, fn {id, _pid, _meta} ->
        Value.num(:erlang.phash2(id))
      end)

    Value.list(ids)
  end

  defp queued_tasks(_), do: Value.err(:E_ARGS)

  # task_stack(id) - return call stack of a task
  defp task_stack([{:num, target_id}]) do
    tasks = Alchemoo.Task.list_tasks()
    found = Enum.find(tasks, fn {id, _pid, _meta} -> :erlang.phash2(id) == target_id end)

    case found do
      {_id, pid, _meta} ->
        # Get stack from task process GenServer.call
        context = GenServer.call(pid, :get_context)
        stack = context[:stack] || []
        # Standard MOO format: list of lists
        # {this, verb, owner, player, line_num}
        # (Our stack entries: {this, verb_name, verb_owner, player, line})
        Enum.map(stack, fn entry ->
          Value.list([
            Value.obj(entry.this),
            Value.str(entry.verb_name),
            Value.obj(entry.verb_owner),
            Value.obj(entry.player),
            Value.num(entry[:line] || 0)
          ])
        end)
        |> Value.list()

      nil ->
        Value.err(:E_INVARG)
    end
  end

  defp task_stack(_), do: Value.err(:E_ARGS)

  # kill_task(id) - terminate task
  defp kill_task([{:num, target_id}]) do
    tasks = Alchemoo.Task.list_tasks()
    found = Enum.find(tasks, fn {id, _pid, _meta} -> :erlang.phash2(id) == target_id end)

    case found do
      {_id, pid, _meta} ->
        # Stop the task process
        GenServer.stop(pid, :normal)
        Value.num(1)

      nil ->
        # Task not found - this is E_INVARG in MOO
        Value.err(:E_INVARG)
    end
  end

  defp kill_task(_), do: Value.err(:E_ARGS)

  # raise(error [, message [, value]]) - raise a MOO error
  defp raise_fn([{:err, error}]) do
    throw({:error, error})
  end

  defp raise_fn([{:err, _error}, {:str, message} | _]) do
    # For now, just raise the error code - message/value support can be added to the Task module later
    throw({:error, Value.str(message)})
  end

  defp raise_fn(_), do: Value.err(:E_ARGS)

  # call_function(name, args...) - dynamically call a built-in function
  defp call_function([{:str, name} | args], env) do
    # Dispatch to the public call/3 function
    call(String.to_atom(name), args, env)
  rescue
    _ -> Value.err(:E_VERBNF)
  end

  defp call_function(_, _env), do: Value.err(:E_ARGS)

  # pass(@args) - call same verb on parent
  defp pass_fn(args, env) do
    case {get_task_context(:verb_definer), get_task_context(:verb_name), Map.get(env, :runtime)} do
      {definer_id, verb_name, runtime} when definer_id != nil and verb_name != nil and runtime != nil ->
        execute_parent_verb(definer_id, verb_name, args, env, runtime)

      _ ->
        Value.err(:E_PERM)
    end
  end

  defp execute_parent_verb(definer_id, verb_name, args, env, runtime) do
    case Map.get(runtime.objects, definer_id) do
      nil ->
        # Fallback to DBServer if not in runtime.objects
        case DBServer.get_object(definer_id) do
          {:ok, definer} ->
            do_pass_call(definer.parent, verb_name, args, env, runtime)

          _ ->
            Value.err(:E_INVIND)
        end

      definer ->
        do_pass_call(definer.parent, verb_name, args, env, runtime)
    end
  end

  defp do_pass_call(parent_id, verb_name, args, env, runtime) do
    receiver_id = get_task_context(:this)

    case Alchemoo.Runtime.call_verb(runtime, Value.obj(parent_id), verb_name, args, env, receiver_id) do
      {:ok, result} -> result
      {:error, err} -> err
    end
  end

  # eval(string) - evaluate MOO code synchronously
  defp eval_fn([{:str, code}]) do
    # Run the code in a new task but synchronously
    # Inherit current context (this, player, caller)
    # Convert context map to keyword list for Task.run
    context_map = Process.get(:task_context) || %{}
    opts = Enum.into(context_map, [])

    case Alchemoo.Task.run(code, %{}, opts) do
      {:ok, result} ->
        # MOO eval returns {success, value}
        Value.list([Value.num(1), result])

      {:error, reason} ->
        # MOO eval returns {0, error_message}
        Value.list([Value.num(0), Value.str(inspect(reason))])
    end
  end

  defp eval_fn(_), do: Value.err(:E_ARGS)

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
  defp min_fn([{:list, items}]), do: min_fn(items)

  defp min_fn(args) do
    nums = Enum.map(args, fn {:num, n} -> n end)
    Value.num(Enum.min(nums))
  rescue
    _ -> Value.err(:E_ARGS)
  end

  # max(numbers...) - maximum value
  defp max_fn([{:list, items}]), do: max_fn(items)

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

  # sinh(number) - hyperbolic sine
  defp sinh_fn([{:num, n}]) do
    Value.num(trunc(:math.sinh(n) * 1000))
  end

  defp sinh_fn(_), do: Value.err(:E_ARGS)

  # cosh(number) - hyperbolic cosine
  defp cosh_fn([{:num, n}]) do
    Value.num(trunc(:math.cosh(n) * 1000))
  end

  defp cosh_fn(_), do: Value.err(:E_ARGS)

  # tanh(number) - hyperbolic tangent
  defp tanh_fn([{:num, n}]) do
    Value.num(trunc(:math.tanh(n) * 1000))
  end

  defp tanh_fn(_), do: Value.err(:E_ARGS)

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

  # notify(player, text [, no_newline]) - send text to player
  defp notify([{:obj, player_id}, {:str, text}]) do
    notify([Value.obj(player_id), Value.str(text), Value.num(0)])
  end

  defp notify([{:obj, player_id}, {:str, text}, {:num, no_newline}]) do
    # Find connection for this player and send text
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        output = if no_newline != 0, do: text, else: text <> "\n"
        Handler.send_output(handler_pid, output)
        Value.num(1)

      {:error, _} ->
        # Player not connected, fail silently (MOO behavior)
        Value.num(0)
    end
  end

  defp notify(_), do: Value.err(:E_ARGS)

  # notify_except(room, text [, skip_list]) - send text to all in room except skip_list
  defp notify_except_fn([{:obj, room_id}, {:str, text}]) do
    notify_except_fn([Value.obj(room_id), Value.str(text), Value.list([])])
  end

  defp notify_except_fn([{:obj, room_id}, {:str, text}, {:list, skip_list}]) do
    case DBServer.get_object(room_id) do
      {:ok, room} ->
        skip_ids = Enum.map(skip_list, fn {:obj, id} -> id end)

        Enum.each(room.contents, fn obj_id ->
          notify_if_not_skipped(obj_id, text, skip_ids)
        end)

        Value.num(0)

      {:error, err} ->
        Value.err(err)
    end
  end

  defp notify_except_fn(_), do: Value.err(:E_ARGS)

  defp notify_if_not_skipped(obj_id, text, skip_ids) do
    if obj_id not in skip_ids do
      if player?([Value.obj(obj_id)]) == Value.num(1) do
        notify([Value.obj(obj_id), Value.str(text)])
      end
    end
  end

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

  # connected_players([full]) - list of connected player objects or info
  defp connected_players([]) do
    connected_players([Value.num(0)])
  end

  defp connected_players([{:num, full}]) do
    player_info =
      ConnSupervisor.list_connections()
      |> Enum.flat_map(fn pid -> extract_player_info(pid, full != 0) end)

    Value.list(player_info)
  end

  defp connected_players(_), do: Value.err(:E_ARGS)

  defp extract_player_info(pid, full?) do
    case Handler.info(pid) do
      %{player_id: id, state: :logged_in} = info when id != nil ->
        if full?, do: [get_full_player_info(id, info)], else: [Value.obj(id)]

      _ ->
        []
    end
  end

  defp get_full_player_info(id, info) do
    # Get name from DB
    name =
      case DBServer.get_property(id, "name") do
        {:ok, {:str, n}} -> n
        _ -> "Player ##{id}"
      end

    Value.list([
      Value.obj(id),
      Value.str(name),
      Value.num(info.idle_seconds),
      Value.num(System.system_time(:second) - info.connected_at)
    ])
  end

  # connection_name(player) - get connection info
  defp connection_name([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        info = Handler.info(handler_pid)
        Value.str(info.peer_info)

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

  # Security

  # caller_perms() - get current caller permissions
  defp caller_perms([]) do
    case get_task_context(:caller_perms) do
      nil -> Value.obj(0)
      id -> Value.obj(id)
    end
  end

  defp caller_perms(_), do: Value.err(:E_ARGS)

  # set_task_perms(obj) - set current task permissions
  defp set_task_perms([{:obj, obj_id}]) do
    current_perms = get_task_context(:perms) || 2

    # Check if current task is wizard or setting to self
    can_set? =
      case DBServer.get_object(current_perms) do
        {:ok, obj} -> Flags.set?(obj.flags, Flags.wizard())
        _ -> false
      end

    if can_set? or obj_id == current_perms do
      set_task_context(:perms, obj_id)
      set_task_context(:player, obj_id)
      Value.num(1)
    else
      Value.err(:E_PERM)
    end
  end

  defp set_task_perms(_), do: Value.err(:E_ARGS)

  # callers([full]) - get current call stack
  defp callers_fn([]) do
    callers_fn([Value.num(0)])
  end

  defp callers_fn([{:num, full}]) do
    stack = get_task_context(:stack) || []

    Enum.map(stack, fn entry ->
      if full != 0 do
        Value.list([
          Value.obj(entry.this),
          Value.str(entry.verb_name),
          Value.obj(entry.verb_owner),
          Value.obj(entry.player),
          Value.num(entry[:line] || 0),
          Value.obj(entry[:perms] || entry.player)
        ])
      else
        Value.list([
          Value.obj(entry.this),
          Value.str(entry.verb_name),
          Value.obj(entry.verb_owner),
          Value.obj(entry.player)
        ])
      end
    end)
    |> Value.list()
  end

  defp callers_fn(_), do: Value.err(:E_ARGS)

  defp get_task_context(key) do
    case Process.get(:task_context) do
      nil -> nil
      context -> Map.get(context, key)
    end
  end

  defp set_task_context(key, value) do
    context = Process.get(:task_context) || %{}
    new_context = Map.put(context, key, value)
    Process.put(:task_context, new_context)
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
        Value.list([Value.obj(owner), Value.str(format_perms(perms))])

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
      {:ok, {owner, perms, names}} ->
        Value.list([Value.obj(owner), Value.str(format_perms(perms)), Value.str(names)])

      {:error, err} ->
        Value.err(err)
    end
  end

  defp verb_info(_), do: Value.err(:E_ARGS)

  defp format_perms(perms) when is_integer(perms) do
    # Bitmask to string: 1=r, 2=w, 4=x, 8=d (typical MOO)
    r = if (perms &&& 1) != 0, do: "r", else: ""
    w = if (perms &&& 2) != 0, do: "w", else: ""
    x = if (perms &&& 4) != 0, do: "x", else: ""
    d = if (perms &&& 8) != 0, do: "d", else: ""
    r <> w <> x <> d
  end

  defp format_perms(perms) when is_binary(perms), do: perms
  defp format_perms(_), do: ""

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
        {:str, p} -> p
        {:num, p} -> Integer.to_string(p)
        _ -> "rx"
      end

    name =
      case Enum.at(info, 2) do
        {:str, n} -> n
        _ -> default_name
      end

    {owner, perms, name}
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

  # verb_code(obj, verb [, full_info]) - get verb code
  defp verb_code([{:obj, obj_id}, {:str, verb_name}]) do
    verb_code([Value.obj(obj_id), Value.str(verb_name), Value.num(0)])
  end

  defp verb_code([{:obj, obj_id}, {:str, verb_name}, {:num, full_info}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        extract_verb_code_info(obj, verb_name, full_info != 0)

      {:error, err} ->
        Value.err(err)
    end
  end

  defp verb_code(_), do: Value.err(:E_ARGS)

  defp extract_verb_code_info(obj, verb_name, full_info?) do
    case Enum.find(obj.verbs, fn v -> matches_verb?(v, verb_name) end) do
      nil ->
        Value.err(:E_VERBNF)

      verb ->
        code_lines = Enum.map(verb.code, &Value.str/1)

        if full_info? do
          Value.list([
            Value.list(code_lines),
            Value.obj(verb.owner),
            Value.str(format_perms(verb.perms)),
            Value.str(verb.name),
            format_verb_args(verb.args)
          ])
        else
          Value.list(code_lines)
        end
    end
  end

  defp matches_verb?(verb, verb_name) do
    # Use same logic as DBServer
    verb.name
    |> String.split(" ")
    |> Enum.any?(fn pattern ->
      match_pattern?(pattern, verb_name)
    end)
  end

  defp match_pattern?(pattern, input) do
    case String.split(pattern, "*", parts: 2) do
      [_exact] ->
        pattern == input

      [prefix, rest] ->
        full = prefix <> rest
        String.starts_with?(input, prefix) and String.starts_with?(full, input)
    end
  end

  defp format_verb_args({dobj, prep, iobj}) do
    Value.list([
      Value.str(Atom.to_string(dobj)),
      Value.str(Atom.to_string(prep)),
      Value.str(Atom.to_string(iobj))
    ])
  end

  # add_verb(obj, info, args) - add verb
  defp add_verb([{:obj, obj_id}, {:list, info}, {:list, args}]) do
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

    verb_args = extract_verb_args(args)

    case DBServer.add_verb(obj_id, name, owner, perms, verb_args) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp add_verb(_), do: Value.err(:E_ARGS)

  defp extract_verb_args(args) do
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

    {dobj, prep, iobj}
  end

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

  # function_info(name) - get built-in function metadata
  defp function_info([{:str, name}]) do
    # Return {min_args, max_args, types}
    # Types is a list of type codes: 0=num, 1=obj, 2=str, 3=err, 4=list, -1=any
    info = get_function_signature(name)

    Value.list(
      Enum.map(info, fn
        val when is_integer(val) -> Value.num(val)
        val when is_list(val) -> Value.list(Enum.map(val, &Value.num/1))
      end)
    )
  end

  defp function_info(_), do: Value.err(:E_ARGS)

  defp get_function_signature(name) do
    signatures = %{
      "typeof" => [1, 1, [any_type()]],
      "tostr" => [0, -1, []],
      "toint" => [1, 1, [any_type()]],
      "toobj" => [1, 1, [any_type()]],
      "length" => [1, 1, [any_type()]],
      "notify" => [2, 3, [1, 2, 0]],
      "player" => [0, 0, []],
      "caller" => [0, 0, []],
      "this" => [0, 0, []],
      "random" => [0, 1, [0]],
      "suspend" => [1, 1, [0]],
      "read" => [0, 1, [1]]
    }

    Map.get(signatures, name, [0, -1, []])
  end

  defp any_type, do: -1

  # disassemble(obj, verb) - return compiled code representation
  defp disassemble([{:obj, obj_id}, {:str, verb_name}]) do
    verb_code([Value.obj(obj_id), Value.str(verb_name)])
  end

  defp disassemble(_), do: Value.err(:E_ARGS)

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
      :ok -> Value.num(1)
      {:ok, _} -> Value.num(1)
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

  # decode_binary(str) - decode binary string (MOO ~XX format)
  defp decode_binary([{:str, str}]) do
    decoded = do_decode_binary(str)
    Value.str(decoded)
  rescue
    _ -> Value.err(:E_INVARG)
  end

  defp decode_binary(_), do: Value.err(:E_ARGS)

  defp do_decode_binary(str) do
    Regex.replace(~r/~([0-9A-Fa-f]{2}|~)/, str, fn _, match ->
      case match do
        "~" ->
          "~"

        hex ->
          <<byte>> = Base.decode16!(String.upcase(hex))
          <<byte>>
      end
    end)
  end

  # encode_binary(str) - encode to binary string (MOO ~XX format)
  defp encode_binary([{:str, str}]) do
    encoded =
      str
      |> String.to_charlist()
      |> Enum.map_join(fn
        char when char in ?\s..?~ and char != ?~ -> <<char>>
        ?~ -> "~~"
        char -> "~" <> Base.encode16(<<char>>)
      end)

    Value.str(encoded)
  end

  defp encode_binary(_), do: Value.err(:E_ARGS)

  # crypt(string [, salt]) - one-way hashing
  defp crypt([{:str, text}]) do
    # Generate a random 2-character salt if not provided
    salt =
      for _ <- 1..2, into: "", do: <<Enum.random(?a..?z)>>

    crypt([Value.str(text), Value.str(salt)])
  end

  defp crypt([{:str, text}, {:str, salt}]) do
    # MOO crypt traditionally uses only the first 2 characters of the salt
    short_salt = String.slice(salt, 0, 2)
    hash = :crypto.hash(:sha256, short_salt <> text) |> Base.encode16(case: :lower)
    Value.str(short_salt <> String.slice(hash, 0, 10))
  end

  defp crypt(_), do: Value.err(:E_ARGS)

  # binary_hash(string) - SHA-1 hash of a string
  defp binary_hash([{:str, str}]) do
    hash = :crypto.hash(:sha, str) |> Base.encode16(case: :lower)
    Value.str(hash)
  end

  defp binary_hash(_), do: Value.err(:E_ARGS)

  # value_hash(value [, algorithm]) - hash any value
  defp value_hash_fn([val]) do
    value_hash_fn([val, Value.str("md5")])
  end

  defp value_hash_fn([val, {:str, algorithm}]) do
    literal = Value.to_literal(val)

    algo_atom =
      case String.downcase(algorithm) do
        "md5" -> :md5
        "sha1" -> :sha
        "sha" -> :sha
        "sha256" -> :sha256
        _ -> nil
      end

    if algo_atom do
      hash = :crypto.hash(algo_atom, literal) |> Base.encode16(case: :lower)
      Value.str(hash)
    else
      Value.err(:E_INVARG)
    end
  end

  defp value_hash_fn(_), do: Value.err(:E_ARGS)

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

  # reverse(list_or_str) - reverse list or string
  defp reverse_fn([{:list, items}]) do
    Value.list(Enum.reverse(items))
  end

  defp reverse_fn([{:str, str}]) do
    Value.str(String.reverse(str))
  end

  defp reverse_fn(_), do: Value.err(:E_ARGS)

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
  defp server_log([message | _]) do
    Logger.info("MOO: #{Value.to_literal(message)}")
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

  # chown(obj, owner) - change object owner
  defp chown([{:obj, obj_id}, {:obj, owner_id}]) do
    case DBServer.chown_object(obj_id, owner_id) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  defp chown(_), do: Value.err(:E_ARGS)

  # renumber(obj) - renumber an object to the lowest available ID
  defp renumber([{:obj, obj_id}]) do
    case DBServer.renumber_object(obj_id) do
      {:ok, new_id} -> Value.obj(new_id)
      {:error, err} -> Value.err(err)
    end
  end

  defp renumber(_), do: Value.err(:E_ARGS)

  # reset_max_object() - reset max_object to the highest current ID
  defp reset_max_object([]) do
    DBServer.reset_max_object()
    Value.num(0)
  end

  defp reset_max_object(_), do: Value.err(:E_ARGS)

  # match_object(string, objects) - find object by name/alias in list
  defp match_object_fn([{:str, name}, {:list, objects}], env) do
    search_name = String.downcase(name)

    case resolve_special_object(search_name) do
      {:ok, obj} -> obj
      :not_special -> find_match_in_list(search_name, objects, env)
    end
  end

  defp match_object_fn(_, _env), do: Value.err(:E_ARGS)

  defp resolve_special_object("me"), do: {:ok, Value.obj(get_task_context(:player) || 2)}

  defp resolve_special_object("here") do
    player_id = get_task_context(:player) || 2

    case DBServer.get_object(player_id) do
      {:ok, player} -> {:ok, Value.obj(player.location)}
      _ -> {:ok, Value.obj(-1)}
    end
  end

  defp resolve_special_object("#" <> id_str) do
    case Integer.parse(id_str) do
      {id, ""} -> {:ok, Value.obj(id)}
      _ -> {:ok, Value.obj(-1)}
    end
  end

  defp resolve_special_object(_), do: :not_special

  defp find_match_in_list(name, objects, env) do
    # Try exact name match first
    result =
      Enum.find_value(objects, nil, fn
        {:obj, id} ->
          if object_matches_name?(id, name, env), do: {:obj, id}, else: nil

        _ ->
          nil
      end)

    result || Value.obj(-1)
  end

  defp object_matches_name?(id, name, env) do
    case get_object_for_match(id, env) do
      {:ok, obj} ->
        # Check name
        if String.downcase(obj.name) == name do
          true
        else
          # Check aliases property if it exists
          check_aliases(obj, name, env)
        end

      _ ->
        false
    end
  end

  defp get_object_for_match(id, env) do
    runtime = Map.get(env, :runtime)

    if runtime do
      case Map.get(runtime.objects, id) do
        nil -> DBServer.get_object(id)
        obj -> {:ok, obj}
      end
    else
      DBServer.get_object(id)
    end
  end

  defp check_aliases(obj, name, env) do
    runtime = Map.get(env, :runtime)

    aliases =
      if runtime do
        case Alchemoo.Runtime.get_property(runtime, Value.obj(obj.id), "aliases") do
          {:ok, {:list, items}} -> items
          _ -> []
        end
      else
        case DBServer.get_property(obj.id, "aliases") do
          {:ok, {:list, items}} -> items
          _ -> []
        end
      end

    Enum.any?(aliases, fn
      {:str, s} -> String.downcase(s) == name
      _ -> false
    end)
  end

  # boot_player(player) - disconnect player
  defp boot_player([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        Handler.close(handler_pid)
        Value.num(1)

      {:error, _} ->
        Value.num(0)
    end
  end

  defp boot_player(_), do: Value.err(:E_ARGS)

  # flush_input([player]) - flush input for player
  defp flush_input_fn([]) do
    player_id = get_task_context(:player) || 2
    flush_input_fn([Value.obj(player_id)])
  end

  defp flush_input_fn([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        Handler.flush_input(handler_pid)
        Value.num(0)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp flush_input_fn(_), do: Value.err(:E_ARGS)

  # connection_options(player) - list available connection options
  defp connection_options([]) do
    player_id = get_task_context(:player) || 2
    connection_options([Value.obj(player_id)])
  end

  defp connection_options([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        options = GenServer.call(handler_pid, :get_connection_options)
        Value.list(Enum.map(options, &Value.str/1))

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp connection_options(_), do: Value.err(:E_ARGS)

  # connection_option(player, option) - get value of a connection option
  defp connection_option([{:obj, player_id}, {:str, name}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        case GenServer.call(handler_pid, {:get_connection_option, name}) do
          [prefix, suffix] when name == "output-delimiters" ->
            Value.list([Value.str(prefix), Value.str(suffix)])

          val when is_integer(val) ->
            Value.num(val)

          val when is_binary(val) ->
            Value.str(val)

          _ ->
            Value.err(:E_INVARG)
        end

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp connection_option([{:str, name}]) do
    player_id = get_task_context(:player) || 2
    connection_option([Value.obj(player_id), Value.str(name)])
  end

  defp connection_option(_), do: Value.err(:E_ARGS)

  # set_connection_option(player, option, value) - set value of a connection option
  defp set_connection_option([{:obj, player_id}, {:str, name}, value]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        # Convert MOO value to internal type
        internal_val =
          case value do
            {:num, n} ->
              n

            {:str, s} ->
              s

            {:list, [{:str, p}, {:str, s}]} when name == "output-delimiters" ->
              [p, s]

            _ ->
              nil
          end

        if internal_val != nil do
          GenServer.cast(handler_pid, {:set_connection_option, name, internal_val})
          Value.num(0)
        else
          Value.err(:E_INVARG)
        end

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp set_connection_option([{:str, name}, value]) do
    player_id = get_task_context(:player) || 2
    set_connection_option([Value.obj(player_id), Value.str(name), value])
  end

  defp set_connection_option(_), do: Value.err(:E_ARGS)

  # output_delimiters([player]) - get output delimiters for player
  defp output_delimiters([]) do
    player_id = get_task_context(:player) || 2
    output_delimiters([Value.obj(player_id)])
  end

  defp output_delimiters([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        [prefix, suffix] = GenServer.call(handler_pid, :get_output_delimiters)
        Value.list([Value.str(prefix), Value.str(suffix)])

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp output_delimiters(_), do: Value.err(:E_ARGS)

  # set_output_delimiters(player, prefix, suffix) - set output delimiters for player
  defp set_output_delimiters([{:obj, player_id}, {:str, prefix}, {:str, suffix}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        GenServer.cast(handler_pid, {:set_output_delimiters, [prefix, suffix]})
        Value.num(0)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp set_output_delimiters(_), do: Value.err(:E_ARGS)

  # player? - check if object is a player
  defp player?([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        if Flags.set?(obj.flags, Flags.user()), do: Value.num(1), else: Value.num(0)

      {:error, _} ->
        Value.num(0)
    end
  end

  defp player?(_), do: Value.err(:E_ARGS)

  # wizard? - check if object is a wizard
  defp wizard?([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        if Flags.set?(obj.flags, Flags.wizard()), do: Value.num(1), else: Value.num(0)

      {:error, _} ->
        Value.num(0)
    end
  end

  defp wizard?(_), do: Value.err(:E_ARGS)

  # players() - list all player objects in database
  defp players_fn([]) do
    # This is expensive, but for small MOOs it's okay
    # We should ideally have a player registry in DBServer
    db = DBServer.get_snapshot()

    player_ids =
      db.objects
      |> Map.values()
      |> Enum.filter(fn obj -> Flags.set?(obj.flags, Flags.user()) end)
      |> Enum.map(fn obj -> Value.obj(obj.id) end)

    Value.list(player_ids)
  end

  defp players_fn(_), do: Value.err(:E_ARGS)

  # idle_seconds(player) - get idle time
  defp idle_seconds([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        info = Handler.info(handler_pid)
        Value.num(info.idle_seconds)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp idle_seconds(_), do: Value.err(:E_ARGS)

  # connected_seconds(player) - get connection time
  defp connected_seconds([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        info = Handler.info(handler_pid)
        Value.num(System.system_time(:second) - info.connected_at)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp connected_seconds(_), do: Value.err(:E_ARGS)

  # memory_usage() - get memory usage
  defp memory_usage([]) do
    usage = :erlang.memory(:total)
    Value.num(usage)
  end

  defp memory_usage(_), do: Value.err(:E_ARGS)

  # db_disk_size() - get database size on disk
  defp db_disk_size([]) do
    stats = DBServer.stats()

    case stats.db_path do
      nil ->
        Value.num(0)

      path ->
        case :file.read_file_info(path) do
          {:ok, info} -> Value.num(elem(info, 1))
          _ -> Value.num(0)
        end
    end
  end

  defp db_disk_size(_), do: Value.err(:E_ARGS)

  # dump_database() - trigger immediate checkpoint
  defp dump_database([]) do
    # Only wizards can dump database (simplified)
    case Alchemoo.Checkpoint.Server.checkpoint() do
      :ok -> Value.num(1)
      _ -> Value.num(0)
    end
  end

  defp dump_database(_), do: Value.err(:E_ARGS)

  # server_started() - get server start time
  defp server_started([]) do
    # Assuming application started when this beam node started
    # Or we could store start time in an Agent/Application env
    # For now, use System.system_time(:second) - uptime
    start_time =
      System.system_time(:second) - div(:erlang.statistics(:wall_clock) |> elem(0), 1000)

    Value.num(start_time)
  end

  defp server_started(_), do: Value.err(:E_ARGS)

  # force_input(player, text [, is_binary]) - insert command into player queue
  defp force_input([{:obj, player_id}, {:str, text}]) do
    force_input([Value.obj(player_id), Value.str(text), Value.num(0)])
  end

  defp force_input([{:obj, player_id}, {:str, text}, {:num, is_binary}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        input_text = if is_binary != 0, do: text, else: text <> "\n"
        Handler.input(handler_pid, input_text)
        Value.num(1)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp force_input(_), do: Value.err(:E_ARGS)

  # read_binary(filename) - read file from restricted directory
  defp read_binary([{:str, filename}]) do
    if wizard?([player_fn([])]) == Value.num(1) do
      # Restrict to 'files/' directory for security
      base_dir = Application.get_env(:alchemoo, :binary_dir, "files")
      # Prevent directory traversal
      clean_filename = Path.basename(filename)
      path = Path.join(base_dir, clean_filename)

      case File.read(path) do
        {:ok, binary} ->
          Value.str(binary)

        {:error, _} ->
          Value.err(:E_INVARG)
      end
    else
      Value.err(:E_PERM)
    end
  end

  defp read_binary(_), do: Value.err(:E_ARGS)

  # object_bytes(obj) - get object size in bytes
  defp object_bytes([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} -> Value.num(:erlang.external_size(obj))
      {:error, err} -> Value.err(err)
    end
  end

  defp object_bytes(_), do: Value.err(:E_ARGS)

  # value_bytes(value) - get value size in bytes
  defp value_bytes([val]) do
    Value.num(:erlang.external_size(val))
  end

  defp value_bytes(_), do: Value.err(:E_ARGS)

  # ticks_left() - get remaining ticks
  defp ticks_left([]) do
    case Process.get(:ticks_remaining) do
      nil -> Value.num(0)
      ticks -> Value.num(ticks)
    end
  end

  defp ticks_left(_), do: Value.err(:E_ARGS)

  # seconds_left() - get remaining seconds
  defp seconds_left([]) do
    case get_task_context(:started_at) do
      nil ->
        Value.num(30)

      started_at ->
        elapsed = System.monotonic_time(:second) - started_at
        Value.num(max(0, 30 - elapsed))
    end
  end

  defp seconds_left(_), do: Value.err(:E_ARGS)

  # set_player_flag(obj, flag) - set USER flag
  defp set_player_flag([{:obj, obj_id}, {:num, flag}]) do
    case DBServer.set_player_flag(obj_id, flag != 0) do
      :ok -> Value.num(1)
      {:error, err} -> Value.err(err)
    end
  end

  defp set_player_flag(_), do: Value.err(:E_ARGS)

  defp check_password_fn([{:obj, player_id}, {:str, password}]) do
    case DBServer.get_property(player_id, "password") do
      {:ok, {:str, hash}} ->
        # Verify hash
        case crypt([Value.str(password), Value.str(hash)]) do
          {:str, ^hash} -> Value.num(1)
          _ -> Value.num(0)
        end

      _ ->
        # If no password set, allow empty password
        if password == "", do: Value.num(1), else: Value.num(0)
    end
  end

  defp check_password_fn(_), do: Value.err(:E_ARGS)

  # buffered_output_length([player]) - get output queue size
  defp buffered_output_length([]) do
    player_id = get_task_context(:player) || 2
    buffered_output_length([Value.obj(player_id)])
  end

  defp buffered_output_length([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        # Need to expose queue length in Handler.info
        info = Handler.info(handler_pid)
        # Note: Handler.info needs to be updated to include queue length
        Value.num(Map.get(info, :output_queue_length, 0))

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  defp buffered_output_length(_), do: Value.err(:E_ARGS)

  # listen(obj, point) - start listening for connections
  defp listen([{:obj, _obj}, {:num, _point}]) do
    if wizard?([Value.obj(get_task_context(:perms) || 2)]) == Value.num(1) do
      # TODO: Implement dynamic listener starting via Network.Supervisor
      Value.err(:E_PERM)
    else
      Value.err(:E_PERM)
    end
  end

  defp listen(_), do: Value.err(:E_ARGS)

  # unlisten(point) - stop listening
  defp unlisten([{:num, _point}]) do
    if wizard?([Value.obj(get_task_context(:perms) || 2)]) == Value.num(1) do
      # TODO: Implement dynamic listener stopping
      Value.err(:E_PERM)
    else
      Value.err(:E_PERM)
    end
  end

  defp unlisten(_), do: Value.err(:E_ARGS)

  # open_network_connection(host, port) - open outbound connection
  defp open_network_connection([{:str, _host}, {:num, _port}]) do
    # TODO: Implement outbound TCP connections
    # Requires configuration to allow specific hosts/ports
    Value.err(:E_PERM)
  end

  defp open_network_connection(_), do: Value.err(:E_ARGS)

  # queue_info([task_id]) - get info about queued tasks
  defp queue_info([]) do
    # List all tasks
    tasks = Alchemoo.Task.list_tasks()

    ids =
      Enum.map(tasks, fn {id, _pid, _meta} ->
        Value.num(:erlang.phash2(id))
      end)

    Value.list(ids)
  end

  defp queue_info([{:num, target_id}]) do
    tasks = Alchemoo.Task.list_tasks()
    found = Enum.find(tasks, fn {id, _pid, _meta} -> :erlang.phash2(id) == target_id end)

    case found do
      {_id, _pid, meta} ->
        # Return info list: {player, start_time, ticks_used, verb_name}
        # (Simplified based on available metadata)
        Value.list([
          Value.obj(meta.player),
          Value.num(meta.started_at),
          Value.num(0),
          Value.str(meta[:verb_name] || "")
        ])

      nil ->
        Value.err(:E_INVARG)
    end
  end

  defp queue_info(_), do: Value.err(:E_ARGS)

  # Extended Math

  defp tan_fn([{:num, n}]), do: Value.num(trunc(:math.tan(n) * 1000))
  defp tan_fn(_), do: Value.err(:E_ARGS)

  defp asin_fn([{:num, n}]), do: Value.num(trunc(:math.asin(n) * 1000))
  defp asin_fn(_), do: Value.err(:E_ARGS)

  defp acos_fn([{:num, n}]), do: Value.num(trunc(:math.acos(n) * 1000))
  defp acos_fn(_), do: Value.err(:E_ARGS)

  defp atan_fn([{:num, n}]), do: Value.num(trunc(:math.atan(n) * 1000))
  defp atan_fn(_), do: Value.err(:E_ARGS)

  defp atan2_fn([{:num, y}, {:num, x}]), do: Value.num(trunc(:math.atan2(y, x) * 1000))
  defp atan2_fn(_), do: Value.err(:E_ARGS)

  defp exp_fn([{:num, n}]), do: Value.num(trunc(:math.exp(n) * 1000))
  defp exp_fn(_), do: Value.err(:E_ARGS)

  defp log_fn([{:num, n}]) when n > 0, do: Value.num(trunc(:math.log(n) * 1000))
  defp log_fn(_), do: Value.err(:E_ARGS)

  defp log10_fn([{:num, n}]) when n > 0, do: Value.num(trunc(:math.log10(n) * 1000))
  defp log10_fn(_), do: Value.err(:E_ARGS)

  defp ceil_fn([{:num, n}]), do: Value.num(n)
  defp ceil_fn(_), do: Value.err(:E_ARGS)

  defp floor_fn([{:num, n}]), do: Value.num(n)
  defp floor_fn(_), do: Value.err(:E_ARGS)

  defp trunc_fn([{:num, n}]), do: Value.num(n)
  defp trunc_fn(_), do: Value.err(:E_ARGS)

  # floatstr(number, precision) - format as float string
  defp floatstr([{:num, n}, {:num, precision}]) do
    # Treat n as scaled integer (x1000)
    integer_part = div(n, 1000)
    fractional_part = abs(rem(n, 1000))

    # Format fractional part to 3 digits then slice to precision
    frac_str =
      fractional_part
      |> Integer.to_string()
      |> String.pad_leading(3, "0")
      |> String.slice(0, precision)

    Value.str("#{integer_part}.#{frac_str}")
  end

  defp floatstr(_), do: Value.err(:E_ARGS)
end
