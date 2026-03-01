defmodule Alchemoo.Builtins do
  @moduledoc """
  MOO built-in functions.

  Implements the standard LambdaMOO built-in functions.
  """
  require Logger
  import Bitwise

  alias Alchemoo.Builtins.Dispatch
  alias Alchemoo.Connection.Handler
  alias Alchemoo.Connection.Supervisor, as: ConnSupervisor
  alias Alchemoo.Database.Flags
  alias Alchemoo.Database.Server, as: DBServer
  alias Alchemoo.Value

  @doc """
  Call a built-in function by name with arguments.
  """
  def call(name, args) when is_binary(name) do
    call(String.to_existing_atom(name), args, %{})
    |> case do
      {:ok, result, _env} -> result
      other -> other
    end
  rescue
    ArgumentError -> Value.err(:E_VERBNF)
  end

  def call(name, args) when is_atom(name) do
    call(name, args, %{})
    |> case do
      {:ok, result, _env} -> result
      other -> other
    end
  catch
    {:error, err, _env} -> err
    {:error, err} -> err
  end

  @doc """
  Call a built-in function by name with arguments and environment.
  """
  def call(name, args, env) when is_binary(name) do
    call(String.to_existing_atom(name), args, env)
  rescue
    ArgumentError -> throw({:error, Value.err(:E_VERBNF), env})
  end

  def call(name, args, env) when is_atom(name) do
    res = Dispatch.call(name, args, env)

    if trace_builtins?() do
      case res do
        {:ok, val, _} ->
          Logger.debug(
            "Builtin #{name}(#{Enum.map_join(args, ", ", &Value.to_literal/1)}) -> #{Value.to_literal(val)}"
          )

        {:error, err} ->
          Logger.debug(
            "Builtin #{name}(#{Enum.map_join(args, ", ", &Value.to_literal/1)}) -> ERROR: #{inspect(err)}"
          )
      end
    end

    case res do
      {:ok, {:err, _} = err, new_env} ->
        # Standard MOO behavior: built-ins RAISE errors
        throw({:error, err, new_env})

      _ ->
        res
    end
  end

  # Implementation functions
  def typeof([val]) do
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

  def typeof(_), do: Value.err(:E_ARGS)

  # suspend(seconds) - suspend task
  def suspend_fn([{:num, seconds}]) when seconds >= 0 do
    wait_in_task(seconds * 1000)
  end

  def suspend_fn(_), do: Value.err(:E_ARGS)

  # resume(task_id [, value]) - resume suspended task
  def resume_fn([{:num, target_id}]) do
    resume_fn([Value.num(target_id), Value.num(0)])
  end

  def resume_fn([{:num, target_id}, value]) do
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

  def resume_fn(_), do: Value.err(:E_ARGS)

  # yield() - yield execution
  def yield_fn([]) do
    suspend_fn([Value.num(0)])
  end

  def yield_fn(_), do: Value.err(:E_ARGS)

  # read([player]) - read line of input from player
  def read_fn([]) do
    player_id = get_task_context(:player) || 2
    read_fn([Value.obj(player_id)])
  end

  def read_fn([{:obj, player_id}]) do
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

  def read_fn(_), do: Value.err(:E_ARGS)

  def wait_in_task(0), do: :ok

  def wait_in_task(timeout_ms) do
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

  def wait_for_input_or_call do
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
  def task_id([]) do
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

  def task_id(_), do: Value.err(:E_ARGS)

  # queued_tasks() - list all queued/suspended tasks
  def queued_tasks([]) do
    tasks = Alchemoo.Task.list_tasks()
    # MOO expects a list of task IDs
    # Our list_tasks returns [{id, pid, metadata}]
    ids =
      Enum.map(tasks, fn {id, _pid, _meta} ->
        Value.num(:erlang.phash2(id))
      end)

    Value.list(ids)
  end

  def queued_tasks(_), do: Value.err(:E_ARGS)

  # task_stack(id) - return call stack of a task
  def task_stack([{:num, target_id}]) do
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

  def task_stack(_), do: Value.err(:E_ARGS)

  # kill_task(id) - terminate task
  def kill_task([{:num, target_id}]) do
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

  def kill_task(_), do: Value.err(:E_ARGS)

  def raise_fn([{:err, _} = error | _rest]) do
    # In MOO, raise(code, message, value) raises 'code'.
    # The message and value are diagnostic info for the exception handler.
    throw({:error, error})
  end

  def raise_fn([{:str, _} = error | _rest]) do
    # MOO also allows raising strings as errors.
    throw({:error, error})
  end

  def raise_fn(_), do: Value.err(:E_ARGS)

  # call_function(name, args...) - dynamically call a built-in function
  def call_function([{:str, name} | args], env) do
    # Dispatch to the public call/3 function
    call(String.to_atom(name), args, env)
  rescue
    _ -> {:ok, Value.err(:E_VERBNF), env}
  end

  def call_function(_, env), do: {:ok, Value.err(:E_ARGS), env}

  # pass(@args) - call same verb on parent
  def pass_fn(args, env) do
    case {get_task_context(:verb_definer), get_task_context(:verb_name), Map.get(env, :runtime)} do
      {definer_id, verb_name, runtime}
      when definer_id != nil and verb_name != nil and runtime != nil ->
        execute_parent_verb(definer_id, verb_name, args, env, runtime)

      _ ->
        {:ok, Value.err(:E_PERM), env}
    end
  end

  def execute_parent_verb(definer_id, verb_name, args, env, runtime) do
    case Map.get(runtime.objects, definer_id) do
      nil ->
        # Fallback to DBServer if not in runtime.objects
        case DBServer.get_object(definer_id) do
          {:ok, definer} ->
            do_pass_call(definer.parent, verb_name, args, env, runtime)

          _ ->
            {:ok, Value.err(:E_INVIND), env}
        end

      definer ->
        do_pass_call(definer.parent, verb_name, args, env, runtime)
    end
  end

  def do_pass_call(parent_id, verb_name, args, env, runtime) do
    receiver_id = get_task_context(:this)

    case Alchemoo.Runtime.call_verb(
           runtime,
           Value.obj(parent_id),
           verb_name,
           args,
           env,
           receiver_id
         ) do
      {:ok, result, new_runtime} -> {:ok, result, Map.put(env, :runtime, new_runtime)}
      {:error, err} -> throw({:error, err})
    end
  end

  # eval(string) - evaluate MOO code synchronously
  def eval_fn([{:str, code}], env) do
    # Run the code in a new task but synchronously
    # Inherit current context (this, player, caller) from task_context
    context_map = Process.get(:task_context) || %{}
    player_id = Map.get(context_map, :player, 2)

    # Get player's location for 'here'
    here_id =
      case DBServer.get_object(player_id) do
        {:ok, obj} -> obj.location
        _ -> -1
      end

    # Inject 'me' and 'here' into the environment
    eval_env =
      env
      |> Map.put("me", Value.obj(player_id))
      |> Map.put("player", Value.obj(player_id))
      |> Map.put("here", Value.obj(here_id))

    opts = Enum.into(context_map, [])

    # Important: pass the updated env (containing :runtime, me, here)
    case Alchemoo.Task.run(code, eval_env, opts) do
      {:ok, result} ->
        # MOO eval returns {success, value}
        {:ok, Value.list([Value.num(1), result]), env}

      {:error, reason} ->
        # MOO eval returns {0, error_message}
        error_msg =
          case reason do
            {:err, err} -> to_string(err)
            _ -> inspect(reason)
          end

        {:ok, Value.list([Value.num(0), Value.str(error_msg)]), env}
    end
  end

  def eval_fn(_, env), do: {:ok, Value.err(:E_ARGS), env}

  # tostr(values...) - convert to string
  def tostr(args) do
    str = Enum.map_join(args, &Value.to_string/1)
    Value.str(str)
  end

  # toint(value) - convert to integer
  def toint([{:num, n}]), do: Value.num(n)

  def toint([{:str, s}]) do
    case Integer.parse(s) do
      {n, _} -> Value.num(n)
      :error -> Value.num(0)
    end
  end

  def toint([{:obj, n}]), do: Value.num(n)
  def toint([{:err, _}]), do: Value.num(0)
  def toint(_), do: Value.err(:E_ARGS)

  # toobj(value) - convert to object
  def toobj([{:num, n}]), do: Value.obj(n)
  def toobj([{:obj, n}]), do: Value.obj(n)

  def toobj([{:str, s}]) do
    case Integer.parse(s) do
      {n, _} -> Value.obj(n)
      :error -> Value.obj(0)
    end
  end

  def toobj(_), do: Value.err(:E_ARGS)

  # toliteral(value) - convert to literal string
  def toliteral([val]) do
    Value.str(Value.to_literal(val))
  end

  def toliteral(_), do: Value.err(:E_ARGS)

  # length(str_or_list) - get length
  def length_fn([val]) do
    case Value.length(val) do
      {:ok, result} -> result
      {:error, err} -> Value.err(err)
    end
  end

  def length_fn(_), do: Value.err(:E_ARGS)

  # is_member(value, list) - check membership
  def member?([val, {:list, items}]) do
    case Enum.any?(items, &Value.equal?(&1, val)) do
      true -> Value.num(1)
      false -> Value.num(0)
    end
  end

  def member?(_), do: Value.err(:E_ARGS)

  # listappend(list, value [, index]) - append to list
  def listappend([{:list, items}, val]) do
    Value.list(items ++ [val])
  end

  def listappend([{:list, items}, val, {:num, idx}]) when idx >= 0 do
    if idx <= length(items) do
      {before, after_list} = Enum.split(items, idx)
      Value.list(before ++ [val] ++ after_list)
    else
      Value.err(:E_RANGE)
    end
  end

  def listappend([{:list, _}, _, _]), do: Value.err(:E_TYPE)
  def listappend(_), do: Value.err(:E_ARGS)

  # listinsert(list, value [, index]) - insert into list
  def listinsert([{:list, items}, val]) do
    Value.list([val | items])
  end

  def listinsert([{:list, items}, val, {:num, idx}]) when idx >= 1 do
    if idx <= length(items) + 1 do
      {before, after_list} = Enum.split(items, idx - 1)
      Value.list(before ++ [val] ++ after_list)
    else
      Value.err(:E_RANGE)
    end
  end

  def listinsert([{:list, _}, _, _]), do: Value.err(:E_TYPE)
  def listinsert(_), do: Value.err(:E_ARGS)

  # listdelete(list, index) - delete from list
  def listdelete([{:list, items}, {:num, idx}]) do
    if idx > 0 and idx <= length(items) do
      Value.list(List.delete_at(items, idx - 1))
    else
      Value.err(:E_RANGE)
    end
  end

  def listdelete([{:list, _}, _]), do: Value.err(:E_TYPE)
  def listdelete(_), do: Value.err(:E_ARGS)

  # listset(list, value, index) - set list element
  def listset([{:list, items}, val, {:num, idx}]) do
    if idx > 0 and idx <= length(items) do
      Value.list(List.replace_at(items, idx - 1, val))
    else
      Value.err(:E_RANGE)
    end
  end

  def listset([{:list, _}, _, _]), do: Value.err(:E_TYPE)
  def listset(_), do: Value.err(:E_ARGS)

  # equal(val1, val2) - test equality
  def equal([val1, val2]) do
    case Value.equal?(val1, val2) do
      true -> Value.num(1)
      false -> Value.num(0)
    end
  end

  def equal(_), do: Value.err(:E_ARGS)

  # random([max]) - random number
  def random_fn([]) do
    Value.num(:rand.uniform(1_000_000_000))
  end

  def random_fn([{:num, max}]) when max > 0 do
    Value.num(:rand.uniform(max))
  end

  def random_fn(_), do: Value.err(:E_ARGS)

  # min(numbers...) - minimum value
  def min_fn([{:list, items}]), do: min_fn(items)

  def min_fn(args) do
    nums = Enum.map(args, fn {:num, n} -> n end)
    Value.num(Enum.min(nums))
  rescue
    _ -> Value.err(:E_ARGS)
  end

  # max(numbers...) - maximum value
  def max_fn([{:list, items}]), do: max_fn(items)

  def max_fn(args) do
    nums = Enum.map(args, fn {:num, n} -> n end)
    Value.num(Enum.max(nums))
  rescue
    _ -> Value.err(:E_ARGS)
  end

  # abs(number) - absolute value
  def abs_fn([{:num, n}]) do
    Value.num(abs(n))
  end

  def abs_fn(_), do: Value.err(:E_ARGS)

  # sqrt(number) - square root
  def sqrt_fn([{:num, n}]) when n >= 0 do
    Value.num(trunc(:math.sqrt(n)))
  end

  def sqrt_fn(_), do: Value.err(:E_ARGS)

  # sin(number) - sine
  def sin_fn([{:num, n}]) do
    Value.num(trunc(:math.sin(n) * 1000))
  end

  def sin_fn(_), do: Value.err(:E_ARGS)

  # cos(number) - cosine
  def cos_fn([{:num, n}]) do
    Value.num(trunc(:math.cos(n) * 1000))
  end

  def cos_fn(_), do: Value.err(:E_ARGS)

  # sinh(number) - hyperbolic sine
  def sinh_fn([{:num, n}]) do
    Value.num(trunc(:math.sinh(n) * 1000))
  end

  def sinh_fn(_), do: Value.err(:E_ARGS)

  # cosh(number) - hyperbolic cosine
  def cosh_fn([{:num, n}]) do
    Value.num(trunc(:math.cosh(n) * 1000))
  end

  def cosh_fn(_), do: Value.err(:E_ARGS)

  # tanh(number) - hyperbolic tangent
  def tanh_fn([{:num, n}]) do
    Value.num(trunc(:math.tanh(n) * 1000))
  end

  def tanh_fn(_), do: Value.err(:E_ARGS)

  # time() - current unix timestamp
  def time_fn([]) do
    Value.num(System.system_time(:second))
  end

  def time_fn(_), do: Value.err(:E_ARGS)

  # ctime([time]) - format time as string
  def ctime_fn([]) do
    ctime_fn([Value.num(System.system_time(:second))])
  end

  def ctime_fn([{:num, timestamp}]) do
    dt = DateTime.from_unix!(timestamp)
    Value.str(Calendar.strftime(dt, "%a %b %d %H:%M:%S %Y"))
  end

  def ctime_fn(_), do: Value.err(:E_ARGS)

  ## Output/Communication

  # notify(player, text [, no_newline]) - send text to player
  def notify([{:obj, player_id}, {:str, text}]) do
    notify([Value.obj(player_id), Value.str(text), Value.num(0)])
  end

  def notify([{:obj, player_id}, {:str, text}, {:num, no_newline}]) do
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

  def notify(_), do: Value.err(:E_ARGS)

  # notify_except(room, text [, skip_list]) - send text to all in room except skip_list
  def notify_except_fn([{:obj, room_id}, {:str, text}]) do
    notify_except_fn([Value.obj(room_id), Value.str(text), Value.list([])])
  end

  def notify_except_fn([{:obj, room_id}, {:str, text}, {:list, skip_list}]) do
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

  def notify_except_fn(_), do: Value.err(:E_ARGS)

  def notify_if_not_skipped(obj_id, text, skip_ids) do
    if obj_id not in skip_ids do
      if player?([Value.obj(obj_id)]) == Value.num(1) do
        notify([Value.obj(obj_id), Value.str(text)])
      end
    end
  end

  def find_player_connection(player_id) do
    # Get all connection handlers and find one for this player
    connections = ConnSupervisor.list_connections()

    if trace_connections?() do
      Logger.debug(
        "Finding connection for ##{player_id} among #{length(connections)} connections"
      )
    end

    Enum.find_value(connections, {:error, :not_found}, fn pid ->
      match_player_connection(pid, player_id, Handler.info(pid))
    end)
  end

  defp match_player_connection(pid, player_id, %{player_id: pid_player_id} = info) do
    if trace_connections?() do
      Logger.debug("Connection #{inspect(pid)}: player_id=#{pid_player_id} state=#{info.state}")
    end

    if pid_player_id == player_id, do: {:ok, pid}, else: nil
  end

  defp match_player_connection(_pid, _player_id, _info), do: nil

  defp trace_builtins?, do: Application.get_env(:alchemoo, :trace_builtins, false)
  defp trace_connections?, do: Application.get_env(:alchemoo, :trace_connections, false)

  # connected_players([full]) - list of connected player objects or info
  def connected_players([]) do
    connected_players([Value.num(0)])
  end

  def connected_players([{:num, full_val}]) do
    player_info =
      ConnSupervisor.list_connections()
      |> Enum.flat_map(fn pid -> extract_player_info(pid, full_val != 0) end)

    Value.list(player_info)
  end

  def connected_players(_), do: Value.err(:E_ARGS)

  def extract_player_info(pid, full?) do
    case Handler.info(pid) do
      %{player_id: id, state: :logged_in} = info when id != nil ->
        if full?, do: [get_full_player_info(id, info)], else: [Value.obj(id)]

      _ ->
        []
    end
  end

  def get_full_player_info(id, info) do
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
  def connection_name([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        info = Handler.info(handler_pid)
        Value.str(info.peer_info)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  def connection_name(_), do: Value.err(:E_ARGS)

  ## Context

  # player() - get current player object
  def player_fn([]) do
    case get_task_context(:player) do
      # Default to wizard if no context
      nil -> Value.obj(2)
      player_id -> Value.obj(player_id)
    end
  end

  def player_fn(_), do: Value.err(:E_ARGS)

  # caller() - get calling object
  def caller_fn([]) do
    case get_task_context(:caller) do
      # Default to wizard if no context
      nil -> Value.obj(2)
      caller_id -> Value.obj(caller_id)
    end
  end

  def caller_fn(_), do: Value.err(:E_ARGS)

  # this() - get current object
  def this_fn([]) do
    case get_task_context(:this) do
      # Default to wizard if no context
      nil -> Value.obj(2)
      this_id -> Value.obj(this_id)
    end
  end

  def this_fn(_), do: Value.err(:E_ARGS)

  # Security

  # caller_perms() - get current caller permissions
  def caller_perms([]) do
    case get_task_context(:caller_perms) do
      nil -> Value.obj(0)
      id -> Value.obj(id)
    end
  end

  def caller_perms(_), do: Value.err(:E_ARGS)

  # set_task_perms(obj) - set current task permissions
  def set_task_perms([{:obj, obj_id}]) do
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

  def set_task_perms(_), do: Value.err(:E_ARGS)

  # callers([full]) - get current call stack
  def callers_fn([]) do
    callers_fn([Value.num(0)])
  end

  def callers_fn([{:num, full}]) do
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

  def callers_fn(_), do: Value.err(:E_ARGS)

  def get_task_context(key) do
    case Process.get(:task_context) do
      nil -> nil
      context -> Map.get(context, key)
    end
  end

  def set_task_context(key, value) do
    context = Process.get(:task_context) || %{}
    new_context = Map.put(context, key, value)
    Process.put(:task_context, new_context)
  end

  ## String Operations

  # index(str, substr [, case_matters]) - find substring
  def index_fn([{:str, str}, {:str, substr}]) do
    index_fn([{:str, str}, {:str, substr}, Value.num(0)])
  end

  def index_fn([{:str, _str}, {:str, ""}, _]) do
    Value.num(1)
  end

  def index_fn([{:str, str}, {:str, substr}, {:num, case_matters}]) do
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

  def index_fn(_), do: Value.err(:E_ARGS)

  # rindex(str, substr [, case_matters]) - find substring from end
  def rindex_fn([{:str, str}, {:str, substr}]) do
    rindex_fn([{:str, str}, {:str, substr}, Value.num(0)])
  end

  def rindex_fn([{:str, str}, {:str, ""}, _]) do
    Value.num(String.length(str) + 1)
  end

  def rindex_fn([{:str, str}, {:str, substr}, {:num, case_matters}]) do
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

  def rindex_fn(_), do: Value.err(:E_ARGS)

  # strsub(str, old, new [, case_matters]) - replace substring
  def strsub([{:str, str}, {:str, old}, {:str, new}]) do
    strsub([{:str, str}, {:str, old}, {:str, new}, Value.num(0)])
  end

  def strsub([{:str, str}, {:str, ""}, _, _]), do: Value.str(str)

  def strsub([{:str, str}, {:str, old}, {:str, new}, {:num, case_matters}]) do
    result =
      case case_matters do
        0 ->
          # Case-insensitive replace
          regex = Regex.compile!(Regex.escape(old), "i")
          Regex.replace(regex, str, new)

        _ ->
          String.replace(str, old, new)
      end

    Value.str(result)
  end

  def strsub(_), do: Value.err(:E_ARGS)

  # strcmp(str1, str2) - compare strings
  def strcmp([{:str, str1}, {:str, str2}]) do
    cond do
      str1 < str2 -> Value.num(-1)
      str1 > str2 -> Value.num(1)
      true -> Value.num(0)
    end
  end

  def strcmp(_), do: Value.err(:E_ARGS)

  # explode(str [, delim]) - split string
  def explode([{:str, str}, {:str, ""}]) do
    parts = String.graphemes(str)
    Value.list(Enum.map(parts, &Value.str/1))
  end

  def explode([{:str, str}]) do
    explode([{:str, str}, Value.str(" ")])
  end

  def explode([{:str, str}, {:str, delim}]) do
    parts = String.split(str, delim)
    Value.list(Enum.map(parts, &Value.str/1))
  end

  def explode(_), do: Value.err(:E_ARGS)

  # substitute(template, subs) - string substitution
  def substitute([{:str, template}, {:list, subs}]) do
    case subs do
      [{:num, start_pos}, {:num, _end_pos}, {:list, captures}, {:str, matched_str}] ->
        # Perform substitution
        result = do_substitute(template, start_pos, matched_str, captures)
        Value.str(result)

      _ ->
        Value.err(:E_INVARG)
    end
  end

  def substitute(_), do: Value.err(:E_ARGS)

  def do_substitute(template, start_pos, matched_str, captures) do
    Regex.replace(~r/%([0-9%])/, template, fn _, char ->
      case char do
        "%" -> "%"
        "0" -> matched_str
        digit -> get_capture(digit, start_pos, matched_str, captures)
      end
    end)
  end

  def get_capture(digit, start_pos, matched_str, captures) do
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

  def extract_slice(str, start, len) when start >= 0 and len > 0 do
    String.slice(str, start, len)
  end

  def extract_slice(_str, _start, _len), do: ""

  ## Object Operations

  # valid(obj) - check if object exists
  def valid([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, _} -> Value.num(1)
      {:error, _} -> Value.num(0)
    end
  end

  def valid(_), do: Value.err(:E_ARGS)

  # parent(obj) - get parent object
  def parent_fn([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} -> Value.obj(obj.parent)
      {:error, err} -> Value.err(err)
    end
  end

  def parent_fn(_), do: Value.err(:E_ARGS)

  # children(obj) - get child objects
  def children([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        # Collect all children by traversing sibling chain
        children = collect_children(obj.first_child_id)
        Value.list(Enum.map(children, &Value.obj/1))

      {:error, err} ->
        Value.err(err)
    end
  end

  def children(_), do: Value.err(:E_ARGS)

  def collect_children(-1), do: []

  def collect_children(child_id) do
    case DBServer.get_object(child_id) do
      {:ok, child} -> [child_id | collect_children(child.sibling_id)]
      {:error, _} -> []
    end
  end

  # max_object() - get highest object number ever created
  def max_object([]) do
    stats = DBServer.stats()
    Value.num(stats.max_object)
  end

  def max_object(_), do: Value.err(:E_ARGS)

  ## Property Operations

  # properties(obj) - list property names
  def properties([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        prop_names = Enum.map(obj.properties, fn prop -> Value.str(prop.name) end)
        Value.list(prop_names)

      {:error, err} ->
        Value.err(err)
    end
  end

  def properties(_), do: Value.err(:E_ARGS)

  # property_info(obj, prop) - get property info
  def property_info([{:obj, obj_id}, {:str, prop_name}]) do
    case DBServer.get_property_info(obj_id, prop_name) do
      {:ok, {owner, perms}} ->
        Value.list([Value.obj(owner), Value.str(format_perms(perms))])

      {:error, err} ->
        Value.err(err)
    end
  end

  def property_info(_), do: Value.err(:E_ARGS)

  # set_property_info(obj, prop, info) - set property info
  def set_property_info([{:obj, obj_id}, {:str, prop_name}, {:list, info}]) do
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

  def set_property_info(_), do: Value.err(:E_ARGS)

  # is_clear_property(obj, prop) - check if property is clear
  def clear_property?([{:obj, obj_id}, {:str, prop_name}]) do
    case DBServer.clear_property?(obj_id, prop_name) do
      {:ok, result} ->
        case result do
          true -> Value.num(1)
          false -> Value.num(0)
        end

      {:error, err} ->
        Value.err(err)
    end
  end

  def clear_property?(_), do: Value.err(:E_ARGS)

  ## Property Access

  # get_property(obj, prop) - get property value
  def get_property([{:obj, obj_id}, {:str, prop_name}]) do
    case DBServer.get_property(obj_id, prop_name) do
      {:ok, value} -> value
      {:error, err} -> Value.err(err)
    end
  end

  def get_property(_), do: Value.err(:E_ARGS)

  # set_property(obj, prop, value) - set property value
  def set_property([{:obj, obj_id}, {:str, prop_name}, value]) do
    case DBServer.set_property(obj_id, prop_name, value) do
      :ok -> value
      {:error, err} -> Value.err(err)
    end
  end

  def set_property(_), do: Value.err(:E_ARGS)

  ## List Operations (Set)

  # setadd(list, value) - add value to list if not present (set semantics)
  def setadd([{:list, items}, value]) do
    case Enum.any?(items, fn item -> Value.equal?(item, value) end) do
      true ->
        Value.list(items)

      false ->
        Value.list(items ++ [value])
    end
  end

  def setadd(_), do: Value.err(:E_ARGS)

  # setremove(list, value) - remove value from list (set semantics)
  def setremove([{:list, items}, value]) do
    new_items = Enum.reject(items, fn item -> Value.equal?(item, value) end)
    Value.list(new_items)
  end

  def setremove(_), do: Value.err(:E_ARGS)

  ## Object Management

  # create(parent) - create new object
  def create([{:obj, parent_id}]) do
    case DBServer.create_object(parent_id) do
      {:ok, new_id} -> Value.obj(new_id)
      {:error, err} -> Value.err(err)
    end
  end

  def create(_), do: Value.err(:E_ARGS)

  # recycle(obj) - delete object
  def recycle([{:obj, obj_id}]) do
    case DBServer.recycle_object(obj_id) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  def recycle(_), do: Value.err(:E_ARGS)

  # chparent(obj, parent) - change parent
  def chparent([{:obj, obj_id}, {:obj, parent_id}]) do
    case DBServer.change_parent(obj_id, parent_id) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  def chparent(_), do: Value.err(:E_ARGS)

  # move(obj, dest) - move object to new location
  def move([{:obj, obj_id}, {:obj, dest_id}]) do
    case DBServer.move_object(obj_id, dest_id) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  def move(_), do: Value.err(:E_ARGS)

  ## Verb Management

  # verbs(obj) - list verbs on object
  def verbs([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        verb_names = Enum.map(obj.verbs, fn v -> Value.str(v.name) end)
        Value.list(verb_names)

      {:error, err} ->
        Value.err(err)
    end
  end

  def verbs(_), do: Value.err(:E_ARGS)

  # verb_info(obj, verb) - get verb info
  def verb_info([{:obj, obj_id}, verb_desc]) do
    with {:ok, verb_name} <- resolve_verb_desc(obj_id, verb_desc),
         {:ok, {owner, perms, names}} <- DBServer.get_verb_info(obj_id, verb_name) do
      Value.list([Value.obj(owner), Value.str(format_perms(perms)), Value.str(names)])
    else
      {:error, err} ->
        Value.err(err)

      _ ->
        Value.err(:E_ARGS)
    end
  end

  def verb_info(_), do: Value.err(:E_ARGS)

  defp resolve_verb_desc(_obj_id, {:str, verb_name}), do: {:ok, verb_name}

  defp resolve_verb_desc(obj_id, {:num, index}) when index > 0 do
    with {:ok, obj} <- DBServer.get_object(obj_id) do
      case Enum.at(obj.verbs, index - 1) do
        nil -> {:error, :E_VERBNF}
        verb -> {:ok, verb.name |> String.split(" ") |> List.first() |> String.replace("*", "")}
      end
    end
  end

  defp resolve_verb_desc(_obj_id, {:num, _index}), do: {:error, :E_INVARG}
  defp resolve_verb_desc(_obj_id, _), do: {:error, :E_ARGS}

  def format_perms(perms) when is_integer(perms) do
    # Bitmask to string: 1=r, 2=w, 4=x, 8=d (typical MOO)
    r = if (perms &&& 1) != 0, do: "r", else: ""
    w = if (perms &&& 2) != 0, do: "w", else: ""
    x = if (perms &&& 4) != 0, do: "x", else: ""
    d = if (perms &&& 8) != 0, do: "d", else: ""
    r <> w <> x <> d
  end

  def format_perms(perms) when is_binary(perms), do: perms
  def format_perms(_), do: ""

  # set_verb_info(obj, verb, info) - set verb info
  def set_verb_info([{:obj, obj_id}, verb_desc, {:list, info}]) do
    case resolve_verb_desc(obj_id, verb_desc) do
      {:ok, verb_name} ->
        {owner, perms, name} = extract_verb_info(info, obj_id, verb_name)

        case DBServer.set_verb_info(obj_id, verb_name, {owner, perms, name}) do
          :ok -> Value.num(0)
          {:error, err} -> Value.err(err)
        end

      {:error, err} ->
        Value.err(err)
    end
  end

  def set_verb_info(_), do: Value.err(:E_ARGS)

  def extract_verb_info(info, default_owner, default_name) do
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
  def verb_args([{:obj, obj_id}, verb_desc]) do
    with {:ok, verb_name} <- resolve_verb_desc(obj_id, verb_desc),
         {:ok, {dobj, prep, iobj}} <- DBServer.get_verb_args(obj_id, verb_name) do
      Value.list([
        Value.str(Atom.to_string(dobj)),
        Value.str(Atom.to_string(prep)),
        Value.str(Atom.to_string(iobj))
      ])
    else
      {:error, err} ->
        Value.err(err)

      _ ->
        Value.err(:E_ARGS)
    end
  end

  def verb_args(_), do: Value.err(:E_ARGS)

  # set_verb_args(obj, verb, args) - set verb args
  def set_verb_args([{:obj, obj_id}, verb_desc, {:list, args}]) do
    case resolve_verb_desc(obj_id, verb_desc) do
      {:ok, verb_name} ->
        case DBServer.set_verb_args(obj_id, verb_name, extract_verb_args(args)) do
          :ok -> Value.num(0)
          {:error, err} -> Value.err(err)
        end

      {:error, err} ->
        Value.err(err)
    end
  end

  def set_verb_args(_), do: Value.err(:E_ARGS)

  # verb_code(obj, verb [, full_info]) - get verb code
  def verb_code([{:obj, obj_id}, {:str, verb_name}]) do
    verb_code([Value.obj(obj_id), Value.str(verb_name), Value.num(0)])
  end

  def verb_code([{:obj, obj_id}, {:str, verb_name}, {:num, full_info}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        extract_verb_code_info(obj, verb_name, full_info != 0)

      {:error, err} ->
        Value.err(err)
    end
  end

  def verb_code(_), do: Value.err(:E_ARGS)

  def extract_verb_code_info(obj, verb_name, full_info?) do
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

  def matches_verb?(verb, verb_name) do
    # Use same logic as DBServer
    verb.name
    |> String.split(" ")
    |> Enum.any?(fn pattern ->
      match_pattern?(pattern, verb_name)
    end)
  end

  def match_pattern?(pattern, input) do
    case String.split(pattern, "*", parts: 2) do
      [_exact] ->
        pattern == input

      [prefix, rest] ->
        full = prefix <> rest
        String.starts_with?(input, prefix) and String.starts_with?(full, input)
    end
  end

  def format_verb_args({dobj, prep, iobj}) do
    Value.list([
      Value.str(Atom.to_string(dobj)),
      Value.str(Atom.to_string(prep)),
      Value.str(Atom.to_string(iobj))
    ])
  end

  # add_verb(obj, info, args) - add verb
  def add_verb([{:obj, obj_id}, {:list, info}, {:list, args}]) do
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

  def add_verb(_), do: Value.err(:E_ARGS)

  def extract_verb_args(args) do
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
  def delete_verb([{:obj, obj_id}, {:str, verb_name}]) do
    case DBServer.delete_verb(obj_id, verb_name) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  def delete_verb(_), do: Value.err(:E_ARGS)

  # set_verb_code(obj, verb, code) - set verb code
  def set_verb_code([{:obj, obj_id}, {:str, verb_name}, {:list, code}]) do
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

  def set_verb_code(_), do: Value.err(:E_ARGS)

  # function_info(name) - get built-in function metadata
  def function_info([{:str, name}]) do
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

  def function_info(_), do: Value.err(:E_ARGS)

  def get_function_signature(name) do
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

  def any_type, do: -1

  # disassemble(obj, verb) - return compiled code representation
  def disassemble([{:obj, obj_id}, {:str, verb_name}]) do
    verb_code([Value.obj(obj_id), Value.str(verb_name)])
  end

  def disassemble(_), do: Value.err(:E_ARGS)

  ## Property Management

  # add_property(obj, name, value, info) - add property
  def add_property([{:obj, obj_id}, {:str, name}, value, {:list, info}]) do
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

  def add_property(_), do: Value.err(:E_ARGS)

  # delete_property(obj, name) - delete property
  def delete_property([{:obj, obj_id}, {:str, name}]) do
    case DBServer.delete_property(obj_id, name) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  def delete_property(_), do: Value.err(:E_ARGS)

  # clear_property(obj, name) - clear property to default
  def clear_property([{:obj, obj_id}, {:str, name}]) do
    case DBServer.set_property(obj_id, name, :clear) do
      :ok -> Value.num(1)
      {:ok, _} -> Value.num(1)
      {:error, err} -> Value.err(err)
    end
  end

  def clear_property(_), do: Value.err(:E_ARGS)

  ## String Operations

  # match(str, pattern [, case_matters]) - pattern matching
  def match_fn([{:str, str}, {:str, pattern}]) do
    match_fn([{:str, str}, {:str, pattern}, Value.num(0)])
  end

  def match_fn([{:str, str}, {:str, pattern}, {:num, case_matters}]) do
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

  def match_fn(_), do: Value.err(:E_ARGS)

  # rmatch(str, pattern [, case_matters]) - reverse pattern matching
  def rmatch_fn([{:str, str}, {:str, pattern}]) do
    rmatch_fn([{:str, str}, {:str, pattern}, Value.num(0)])
  end

  def rmatch_fn([{:str, str}, {:str, pattern}, {:num, case_matters}]) do
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

  def rmatch_fn(_), do: Value.err(:E_ARGS)

  # Helper: Convert MOO regex to PCRE
  def moo_to_pcre(moo_pattern) do
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

  def do_moo_to_pcre([], acc), do: acc

  # MOO special: % followed by something
  def do_moo_to_pcre(["%", char | rest], acc) do
    do_moo_to_pcre(rest, [handle_percent_escape(char) | acc])
  end

  # MOO special characters (unguarded)
  def do_moo_to_pcre([char | rest], acc) when char in ~w(. * + ? ^ $ [ ]) do
    do_moo_to_pcre(rest, [char | acc])
  end

  # PCRE special characters that are NOT MOO specials (must be escaped)
  def do_moo_to_pcre([char | rest], acc) when char in ~w[\ ( ) { } |] do
    do_moo_to_pcre(rest, ["\\#{char}" | acc])
  end

  # Normal characters
  def do_moo_to_pcre([char | rest], acc) do
    do_moo_to_pcre(rest, [char | acc])
  end

  def handle_percent_escape("("), do: "("
  def handle_percent_escape(")"), do: ")"
  def handle_percent_escape("|"), do: "|"
  def handle_percent_escape("."), do: "\\."
  def handle_percent_escape("*"), do: "\\*"
  def handle_percent_escape("+"), do: "\\+"
  def handle_percent_escape("?"), do: "\\?"
  def handle_percent_escape("["), do: "\\["
  def handle_percent_escape("]"), do: "\\]"
  def handle_percent_escape("^"), do: "\\^"
  def handle_percent_escape("$"), do: "\\$"
  def handle_percent_escape("%"), do: "%"
  def handle_percent_escape("w"), do: "\\w"
  def handle_percent_escape("W"), do: "\\W"
  def handle_percent_escape("b"), do: "\\b"
  def handle_percent_escape("<"), do: "\\b"
  def handle_percent_escape(">"), do: "\\b"

  def handle_percent_escape(digit) when digit in ~w(1 2 3 4 5 6 7 8 9),
    do: "\\#{digit}"

  def handle_percent_escape(char), do: "\\#{char}"

  # Helper: format captures for MOO
  def format_moo_captures(indices, count) do
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
  def decode_binary([{:str, str}]) do
    decoded = do_decode_binary(str)
    Value.str(decoded)
  rescue
    _ -> Value.err(:E_INVARG)
  end

  def decode_binary(_), do: Value.err(:E_ARGS)

  def do_decode_binary(str) do
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
  def encode_binary([{:str, str}]) do
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

  def encode_binary(_), do: Value.err(:E_ARGS)

  # crypt(string [, salt]) - one-way hashing
  def crypt([{:str, text}]) do
    # Generate a random 2-character salt if not provided
    salt =
      for _ <- 1..2, into: "", do: <<Enum.random(?a..?z)>>

    crypt([Value.str(text), Value.str(salt)])
  end

  def crypt([{:str, text}, {:str, salt}]) do
    # MOO crypt traditionally uses only the first 2 characters of the salt
    short_salt = String.slice(salt, 0, 2)
    hash = :crypto.hash(:sha256, short_salt <> text) |> Base.encode16(case: :lower)
    Value.str(short_salt <> String.slice(hash, 0, 10))
  end

  def crypt(_), do: Value.err(:E_ARGS)

  # binary_hash(string) - SHA-1 hash of a string
  def binary_hash([{:str, str}]) do
    hash = :crypto.hash(:sha, str) |> Base.encode16(case: :lower)
    Value.str(hash)
  end

  def binary_hash(_), do: Value.err(:E_ARGS)

  # value_hash(value [, algorithm]) - hash any value
  def value_hash_fn([val]) do
    value_hash_fn([val, Value.str("md5")])
  end

  def value_hash_fn([val, {:str, algorithm}]) do
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

  def value_hash_fn(_), do: Value.err(:E_ARGS)

  ## List Operations

  # sort(list) - sort list
  def sort_fn([{:list, items}]) do
    sorted =
      Enum.sort(items, fn a, b ->
        compare_values(a, b) <= 0
      end)

    Value.list(sorted)
  end

  def sort_fn(_), do: Value.err(:E_ARGS)

  # reverse(list_or_str) - reverse list or string
  def reverse_fn([{:list, items}]) do
    Value.list(Enum.reverse(items))
  end

  def reverse_fn([{:str, str}]) do
    Value.str(String.reverse(str))
  end

  def reverse_fn(_), do: Value.err(:E_ARGS)

  # Helper: compare MOO values for sorting
  def compare_values({:num, a}, {:num, b}), do: a - b

  def compare_values({:str, a}, {:str, b}) do
    cond do
      a < b -> -1
      a > b -> 1
      true -> 0
    end
  end

  def compare_values({:obj, a}, {:obj, b}), do: a - b

  def compare_values({type_a, _}, {type_b, _}) do
    # Sort by type: num < obj < str < err < list
    type_order = %{num: 0, obj: 1, str: 2, err: 3, list: 4}
    Map.get(type_order, type_a, 5) - Map.get(type_order, type_b, 5)
  end

  ## Server Management

  # server_version() - get server version string
  def server_version([]) do
    Value.str("Alchemoo #{Alchemoo.Version.version()}")
  end

  def server_version(_), do: Value.err(:E_ARGS)

  # server_log(message) - log message to server log
  def server_log([message | _]) do
    Logger.info("MOO: #{Value.to_literal(message)}")
    Value.num(1)
  end

  def server_log(_), do: Value.err(:E_ARGS)

  # shutdown([message]) - shutdown server
  def shutdown([]) do
    shutdown([Value.str("Shutdown by MOO task")])
  end

  def shutdown([{:str, message}]) do
    Logger.warning("Server shutdown triggered by MOO task: #{message}")
    # Trigger application stop after a delay
    spawn(fn ->
      Process.sleep(1000)
      System.stop(0)
    end)

    Value.num(1)
  end

  def shutdown(_), do: Value.err(:E_ARGS)

  # chown(obj, owner) - change object owner
  def chown([{:obj, obj_id}, {:obj, owner_id}]) do
    case DBServer.chown_object(obj_id, owner_id) do
      :ok -> Value.num(0)
      {:error, err} -> Value.err(err)
    end
  end

  def chown(_), do: Value.err(:E_ARGS)

  # renumber(obj) - renumber an object to the lowest available ID
  def renumber([{:obj, obj_id}]) do
    case DBServer.renumber_object(obj_id) do
      {:ok, new_id} -> Value.obj(new_id)
      {:error, err} -> Value.err(err)
    end
  end

  def renumber(_), do: Value.err(:E_ARGS)

  # reset_max_object() - reset max_object to the highest current ID
  def reset_max_object([]) do
    DBServer.reset_max_object()
    Value.num(0)
  end

  def reset_max_object(_), do: Value.err(:E_ARGS)

  # match_object(string, objects) - find object by name/alias in list
  def match_object_fn([{:str, name}, {:list, objects}], env) do
    search_name = String.downcase(name)

    case resolve_special_object(search_name) do
      {:ok, obj} -> obj
      :not_special -> find_match_in_list(search_name, objects, env)
    end
  end

  def match_object_fn(_, _env), do: Value.err(:E_ARGS)

  def resolve_special_object("me"), do: {:ok, Value.obj(get_task_context(:player) || 2)}

  def resolve_special_object("here") do
    player_id = get_task_context(:player) || 2

    case DBServer.get_object(player_id) do
      {:ok, player} -> {:ok, Value.obj(player.location)}
      _ -> {:ok, Value.obj(-1)}
    end
  end

  def resolve_special_object("#" <> id_str) do
    case Integer.parse(id_str) do
      {id, ""} -> {:ok, Value.obj(id)}
      _ -> {:ok, Value.obj(-1)}
    end
  end

  def resolve_special_object(_), do: :not_special

  def find_match_in_list(name, objects, env) do
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

  def object_matches_name?(id, name, env) do
    case get_object_for_match(id, env) do
      {:ok, obj} ->
        check_object_match(obj, name, env)

      _ ->
        false
    end
  end

  defp check_object_match(obj, name, env) do
    cond do
      String.downcase(obj.name) == name ->
        true

      res = check_aliases(obj, name, env) ->
        res

      true ->
        false
    end
  end

  def get_object_for_match(id, env) do
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

  def check_aliases(obj, name, env) do
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
  def boot_player([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        Handler.close(handler_pid)
        Value.num(1)

      {:error, _} ->
        Value.num(0)
    end
  end

  def boot_player(_), do: Value.err(:E_ARGS)

  # flush_input([player]) - flush input for player
  def flush_input_fn([]) do
    player_id = get_task_context(:player) || 2
    flush_input_fn([Value.obj(player_id)])
  end

  def flush_input_fn([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        Handler.flush_input(handler_pid)
        Value.num(0)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  def flush_input_fn(_), do: Value.err(:E_ARGS)

  # connection_options(player) - list available connection options
  def connection_options([]) do
    player_id = get_task_context(:player) || 2
    connection_options([Value.obj(player_id)])
  end

  def connection_options([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        options = GenServer.call(handler_pid, :get_connection_options)
        Value.list(Enum.map(options, &Value.str/1))

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  def connection_options(_), do: Value.err(:E_ARGS)

  # connection_option(player, option) - get value of a connection option
  def connection_option([{:obj, player_id}, {:str, name}]) do
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

  def connection_option([{:str, name}]) do
    player_id = get_task_context(:player) || 2
    connection_option([Value.obj(player_id), Value.str(name)])
  end

  def connection_option(_), do: Value.err(:E_ARGS)

  # set_connection_option(player, option, value) - set value of a connection option
  def set_connection_option([{:obj, player_id}, {:str, name}, value]) do
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

  def set_connection_option([{:str, name}, value]) do
    player_id = get_task_context(:player) || 2
    set_connection_option([Value.obj(player_id), Value.str(name), value])
  end

  def set_connection_option(_), do: Value.err(:E_ARGS)

  # output_delimiters([player]) - get output delimiters for player
  def output_delimiters([]) do
    player_id = get_task_context(:player) || 2
    output_delimiters([Value.obj(player_id)])
  end

  def output_delimiters([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        [prefix, suffix] = GenServer.call(handler_pid, :get_output_delimiters)
        Value.list([Value.str(prefix), Value.str(suffix)])

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  def output_delimiters(_), do: Value.err(:E_ARGS)

  # set_output_delimiters(player, prefix, suffix) - set output delimiters for player
  def set_output_delimiters([{:obj, player_id}, {:str, prefix}, {:str, suffix}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        GenServer.cast(handler_pid, {:set_output_delimiters, [prefix, suffix]})
        Value.num(0)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  def set_output_delimiters(_), do: Value.err(:E_ARGS)

  # player? - check if object is a player
  def player?([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        if Flags.set?(obj.flags, Flags.user()), do: Value.num(1), else: Value.num(0)

      {:error, _} ->
        Value.num(0)
    end
  end

  def player?(_), do: Value.err(:E_ARGS)

  # wizard? - check if object is a wizard
  def wizard?([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} ->
        if Flags.set?(obj.flags, Flags.wizard()), do: Value.num(1), else: Value.num(0)

      {:error, _} ->
        Value.num(0)
    end
  end

  def wizard?(_), do: Value.err(:E_ARGS)

  # players() - list all player objects in database
  def players_fn([]) do
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

  def players_fn(_), do: Value.err(:E_ARGS)

  # idle_seconds(player) - get idle time
  def idle_seconds([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        info = Handler.info(handler_pid)
        Value.num(info.idle_seconds)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  def idle_seconds(_), do: Value.err(:E_ARGS)

  # connected_seconds(player) - get connection time
  def connected_seconds([{:obj, player_id}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        info = Handler.info(handler_pid)
        Value.num(System.system_time(:second) - info.connected_at)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  def connected_seconds(_), do: Value.err(:E_ARGS)

  # memory_usage() - get memory usage
  def memory_usage([]) do
    usage = :erlang.memory(:total)
    Value.num(usage)
  end

  def memory_usage(_), do: Value.err(:E_ARGS)

  # db_disk_size() - get database size on disk
  def db_disk_size([]) do
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

  def db_disk_size(_), do: Value.err(:E_ARGS)

  # dump_database() - trigger immediate checkpoint
  def dump_database([]) do
    # Only wizards can dump database (simplified)
    case Alchemoo.Checkpoint.Server.checkpoint() do
      :ok -> Value.num(1)
      _ -> Value.num(0)
    end
  end

  def dump_database(_), do: Value.err(:E_ARGS)

  # server_started() - get server start time
  def server_started([]) do
    # Assuming application started when this beam node started
    # Or we could store start time in an Agent/Application env
    # For now, use System.system_time(:second) - uptime
    start_time =
      System.system_time(:second) - div(:erlang.statistics(:wall_clock) |> elem(0), 1000)

    Value.num(start_time)
  end

  def server_started(_), do: Value.err(:E_ARGS)

  # force_input(player, text [, is_binary]) - insert command into player queue
  def force_input([{:obj, player_id}, {:str, text}]) do
    force_input([Value.obj(player_id), Value.str(text), Value.num(0)])
  end

  def force_input([{:obj, player_id}, {:str, text}, {:num, is_binary}]) do
    case find_player_connection(player_id) do
      {:ok, handler_pid} ->
        input_text = if is_binary != 0, do: text, else: text <> "\n"
        Handler.input(handler_pid, input_text)
        Value.num(1)

      {:error, _} ->
        Value.err(:E_INVARG)
    end
  end

  def force_input(_), do: Value.err(:E_ARGS)

  # read_binary(filename) - read file from restricted directory
  def read_binary([{:str, filename}]) do
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

  def read_binary(_), do: Value.err(:E_ARGS)

  # object_bytes(obj) - get object size in bytes
  def object_bytes([{:obj, obj_id}]) do
    case DBServer.get_object(obj_id) do
      {:ok, obj} -> Value.num(:erlang.external_size(obj))
      {:error, err} -> Value.err(err)
    end
  end

  def object_bytes(_), do: Value.err(:E_ARGS)

  # value_bytes(value) - get value size in bytes
  def value_bytes([val]) do
    Value.num(:erlang.external_size(val))
  end

  def value_bytes(_), do: Value.err(:E_ARGS)

  # ticks_left() - get remaining ticks
  def ticks_left([]) do
    case Process.get(:ticks_remaining) do
      nil -> Value.num(0)
      ticks -> Value.num(ticks)
    end
  end

  def ticks_left(_), do: Value.err(:E_ARGS)

  # seconds_left() - get remaining seconds
  def seconds_left([]) do
    case get_task_context(:started_at) do
      nil ->
        Value.num(30)

      started_at ->
        elapsed = System.monotonic_time(:second) - started_at
        Value.num(max(0, 30 - elapsed))
    end
  end

  def seconds_left(_), do: Value.err(:E_ARGS)

  # set_player_flag(obj, flag) - set USER flag
  def set_player_flag([{:obj, obj_id}, {:num, flag}]) do
    case DBServer.set_player_flag(obj_id, flag != 0) do
      :ok -> Value.num(1)
      {:error, err} -> Value.err(err)
    end
  end

  def set_player_flag(_), do: Value.err(:E_ARGS)

  def check_password_fn([{:obj, player_id}, {:str, password}]) do
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

  def check_password_fn(_), do: Value.err(:E_ARGS)

  # buffered_output_length([player]) - get output queue size
  def buffered_output_length([]) do
    player_id = get_task_context(:player) || 2
    buffered_output_length([Value.obj(player_id)])
  end

  def buffered_output_length([{:obj, player_id}]) do
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

  def buffered_output_length(_), do: Value.err(:E_ARGS)

  # listen(obj, point) - start listening for connections
  def listen([{:obj, _obj}, {:num, _point}]) do
    if wizard?([Value.obj(get_task_context(:perms) || 2)]) == Value.num(1) do
      # FUTURE: Implement dynamic listener starting via Network.Supervisor
      Value.err(:E_PERM)
    else
      Value.err(:E_PERM)
    end
  end

  def listen(_), do: Value.err(:E_ARGS)

  # unlisten(point) - stop listening
  def unlisten([{:num, _point}]) do
    if wizard?([Value.obj(get_task_context(:perms) || 2)]) == Value.num(1) do
      # FUTURE: Implement dynamic listener stopping
      Value.err(:E_PERM)
    else
      Value.err(:E_PERM)
    end
  end

  def unlisten(_), do: Value.err(:E_ARGS)

  # open_network_connection(host, port) - open outbound connection
  def open_network_connection([{:str, _host}, {:num, _port}]) do
    # FUTURE: Implement outbound TCP connections
    # Requires configuration to allow specific hosts/ports
    Value.err(:E_PERM)
  end

  def open_network_connection(_), do: Value.err(:E_ARGS)

  # queue_info([task_id]) - get info about queued tasks
  def queue_info([]) do
    # List all tasks
    tasks = Alchemoo.Task.list_tasks()

    ids =
      Enum.map(tasks, fn {id, _pid, _meta} ->
        Value.num(:erlang.phash2(id))
      end)

    Value.list(ids)
  end

  def queue_info([{:num, target_id}]) do
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

  def queue_info(_), do: Value.err(:E_ARGS)

  # Extended Math

  def tan_fn([{:num, n}]), do: Value.num(trunc(:math.tan(n) * 1000))
  def tan_fn(_), do: Value.err(:E_ARGS)

  def asin_fn([{:num, n}]), do: Value.num(trunc(:math.asin(n) * 1000))
  def asin_fn(_), do: Value.err(:E_ARGS)

  def acos_fn([{:num, n}]), do: Value.num(trunc(:math.acos(n) * 1000))
  def acos_fn(_), do: Value.err(:E_ARGS)

  def atan_fn([{:num, n}]), do: Value.num(trunc(:math.atan(n) * 1000))
  def atan_fn(_), do: Value.err(:E_ARGS)

  def atan2_fn([{:num, y}, {:num, x}]), do: Value.num(trunc(:math.atan2(y, x) * 1000))
  def atan2_fn(_), do: Value.err(:E_ARGS)

  def exp_fn([{:num, n}]), do: Value.num(trunc(:math.exp(n) * 1000))
  def exp_fn(_), do: Value.err(:E_ARGS)

  def log_fn([{:num, n}]) when n > 0, do: Value.num(trunc(:math.log(n) * 1000))
  def log_fn(_), do: Value.err(:E_ARGS)

  def log10_fn([{:num, n}]) when n > 0, do: Value.num(trunc(:math.log10(n) * 1000))
  def log10_fn(_), do: Value.err(:E_ARGS)

  def ceil_fn([{:num, n}]), do: Value.num(n)
  def ceil_fn(_), do: Value.err(:E_ARGS)

  def floor_fn([{:num, n}]), do: Value.num(n)
  def floor_fn(_), do: Value.err(:E_ARGS)

  def trunc_fn([{:num, n}]), do: Value.num(n)
  def trunc_fn(_), do: Value.err(:E_ARGS)

  # floatstr(number, precision) - format as float string
  def floatstr([{:num, n}, {:num, precision}]) do
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

  def floatstr(_), do: Value.err(:E_ARGS)
end
