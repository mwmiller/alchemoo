defmodule Alchemoo.Task do
  @moduledoc """
  A Task represents a single MOO task execution. Each task runs in its own
  GenServer process with tick quota enforcement, suspend/resume support,
  and crash isolation.
  """
  use GenServer, restart: :temporary
  require Logger

  alias Alchemoo.{Interpreter, Parser, Value}

  # CONFIG: Should be extracted to config
  # CONFIG: :alchemoo, :default_tick_quota
  @default_tick_quota 10_000
  # CONFIG: :alchemoo, :max_tasks_per_player
  @max_tasks_per_player 10

  defstruct [
    :id,
    :verb_code,
    :env,
    :player,
    :this,
    :caller,
    :args,
    # Connection handler for this task
    :handler_pid,
    # Process to send result to for sync execution
    :sync_caller,
    # Current task permissions (object ID)
    :perms,
    ticks_used: 0,
    tick_quota: @default_tick_quota,
    suspended_until: nil,
    result: nil,
    started_at: nil
  ]

  ## Client API

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Run verb code synchronously and return the result.

  Used primarily for testing and simple command execution.
  For production background tasks, use TaskSupervisor.spawn_task/3.
  """
  def run(verb_code, env, opts \\ []) do
    # Check player task limit
    player_id = Keyword.get(opts, :player)

    case player_id && count_player_tasks(player_id) >= @max_tasks_per_player do
      true ->
        {:error, :too_many_tasks}

      _ ->
        task_opts =
          Keyword.merge(
            [
              verb_code: verb_code,
              env: env,
              sync_caller: self()
            ],
            opts
          )

        case start(task_opts) do
          {:ok, pid} ->
            # Check if it already finished before we even monitor
            receive do
              {:task_complete, result} -> {:ok, result}
              {:task_error, reason} -> {:error, reason}
            after
              0 ->
                ref = Process.monitor(pid)

                receive do
                  {:task_complete, result} ->
                    Process.demonitor(ref, [:flush])
                    {:ok, result}

                  {:task_error, reason} ->
                    Process.demonitor(ref, [:flush])
                    {:error, reason}

                  {:DOWN, ^ref, :process, ^pid, {:shutdown, result}} ->
                    {:ok, result}

                  {:DOWN, ^ref, :process, ^pid, reason} ->
                    receive do
                      {:task_complete, result} -> {:ok, result}
                      {:task_error, reason} -> {:error, reason}
                    after
                      0 -> {:error, {:crashed, reason}}
                    end
                after
                  30_011 ->
                    Process.demonitor(ref, [:flush])
                    {:error, :timeout}
                end
            end

          error ->
            error
        end
    end
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Merge context into environment for variable access
    initial_env = Keyword.get(opts, :env, %{})
    player_id = Keyword.get(opts, :player, 2)
    this_id = Keyword.get(opts, :this, 2)
    caller_id = Keyword.get(opts, :caller, 2)
    args = Keyword.get(opts, :args, [])
    verb_name = Keyword.get(opts, :verb_name, "(unknown)")

    env =
      initial_env
      |> Map.put("player", Value.obj(player_id))
      |> Map.put("this", Value.obj(this_id))
      |> Map.put("caller", Value.obj(caller_id))
      |> Map.put("args", Value.list(args))
      # Standard MOO type constants
      |> Map.put("INT", Value.num(0))
      |> Map.put("NUM", Value.num(0))
      |> Map.put("OBJ", Value.num(1))
      |> Map.put("STR", Value.num(2))
      |> Map.put("ERR", Value.num(3))
      |> Map.put("LIST", Value.num(4))
      # Standard MOO error constants
      |> Map.put("E_NONE", Value.err(:E_NONE))
      |> Map.put("E_TYPE", Value.err(:E_TYPE))
      |> Map.put("E_DIV", Value.err(:E_DIV))
      |> Map.put("E_PERM", Value.err(:E_PERM))
      |> Map.put("E_PROPNF", Value.err(:E_PROPNF))
      |> Map.put("E_VERBNF", Value.err(:E_VERBNF))
      |> Map.put("E_VARNF", Value.err(:E_VARNF))
      |> Map.put("E_INVIND", Value.err(:E_INVIND))
      |> Map.put("E_RECMOVE", Value.err(:E_RECMOVE))
      |> Map.put("E_MAXREC", Value.err(:E_MAXREC))
      |> Map.put("E_RANGE", Value.err(:E_RANGE))
      |> Map.put("E_ARGS", Value.err(:E_ARGS))
      |> Map.put("E_NACC", Value.err(:E_NACC))
      |> Map.put("E_INVARG", Value.err(:E_INVARG))
      |> Map.put("E_QUOTA", Value.err(:E_QUOTA))
      |> Map.put("E_FLOAT", Value.err(:E_FLOAT))
      |> Map.put_new("verb", Value.str(verb_name))
      |> Map.put_new("argstr", Value.str(""))
      |> Map.put_new("dobj", Value.obj(-1))
      |> Map.put_new("dobjstr", Value.str(""))
      |> Map.put_new("prepstr", Value.str(""))
      |> Map.put_new("iobj", Value.obj(-1))
      |> Map.put_new("iobjstr", Value.str(""))

    task = %__MODULE__{
      id: make_ref(),
      verb_code: Keyword.fetch!(opts, :verb_code),
      env: env,
      player: player_id,
      this: this_id,
      caller: caller_id,
      args: args,
      handler_pid: Keyword.get(opts, :handler_pid),
      sync_caller: Keyword.get(opts, :sync_caller),
      tick_quota: Keyword.get(opts, :tick_quota, @default_tick_quota),
      perms: Keyword.get(opts, :perms, player_id),
      started_at: System.monotonic_time(:second)
    }

    maybe_log_task_debug(
      "Initializing task #{inspect(task.id)} for verb '#{verb_name}' on ##{this_id}"
    )

    # Registry allows metadata-based lookups (e.g. all tasks for a player)
    Registry.register(Alchemoo.TaskRegistry, task.id, %{
      player: task.player,
      this: task.this,
      caller: task.caller,
      handler_pid: task.handler_pid,
      started_at: System.system_time(:second),
      verb_name: verb_name,
      verb_definer: this_id
    })

    Process.put(:task_context, %{
      id: task.id,
      player: task.player,
      this: task.this,
      caller: task.caller,
      handler_pid: task.handler_pid,
      perms: task.perms,
      caller_perms: Keyword.get(opts, :caller_perms, 0),
      stack: Keyword.get(opts, :stack, []),
      started_at: task.started_at,
      verb_name: verb_name,
      verb_definer: this_id
    })

    {:ok, task, {:continue, :execute}}
  end

  @impl true
  def handle_call(:get_context, _from, task) do
    context = Process.get(:task_context)
    {:reply, context, task}
  end

  @impl true
  def handle_continue(:execute, task) do
    context = Process.get(:task_context)
    verb_name = (context && context[:verb_name]) || "(unknown)"
    maybe_log_task_debug("Starting execution of task #{inspect(task.id)} ('#{verb_name}')")

    case execute_with_quota(task) do
      {:ok, result, new_task} ->
        maybe_log_task_debug("Task #{inspect(task.id)} finished with result: #{inspect(result)}")
        handle_task_success(result, new_task)

      {:quota_exceeded, new_task} ->
        handle_task_quota_exceeded(new_task)

      {:error, reason, new_task} ->
        Logger.error("Task #{inspect(task.id)} failed: #{inspect(reason)}")
        handle_task_error(reason, new_task)
    end
  end

  defp handle_task_success(result, task) do
    case task.sync_caller do
      nil -> :ok
      pid -> send(pid, {:task_complete, result})
    end

    {:stop, {:shutdown, result}, %{task | result: result}}
  end

  defp handle_task_quota_exceeded(task) do
    Logger.warning("Task #{inspect(task.id)} exceeded tick quota")

    case task.sync_caller do
      nil -> :ok
      pid -> send(pid, {:task_error, :E_QUOTA})
    end

    {:stop, {:shutdown, {:error, Value.err(:E_QUOTA)}}, task}
  end

  defp handle_task_error(reason, task) do
    case task.sync_caller do
      nil -> :ok
      pid -> send(pid, {:task_error, reason})
    end

    {:stop, {:shutdown, {:error, reason}}, task}
  end

  ## Private Helpers

  defp execute_with_quota(task) do
    # Parse verb code if it's a string
    ast =
      case task.verb_code do
        code when is_binary(code) ->
          case Parser.MOOSimple.parse(code) do
            {:ok, ast} ->
              ast

            {:error, _reason} ->
              throw({:error, Value.err(:E_VERBNF)})
          end

        ast ->
          ast
      end

    # Initialize ticks in process dictionary
    Process.put(:ticks_remaining, task.tick_quota - task.ticks_used)

    # Execute with tick counting
    try do
      {result, final_env} = execute_statements(ast.statements, task.env)

      ticks_used = task.tick_quota - task.ticks_used - Process.get(:ticks_remaining)
      new_task = %{task | ticks_used: task.ticks_used + ticks_used, env: final_env}
      {:ok, result, new_task}
    catch
      {:return, value} ->
        ticks_used = task.tick_quota - task.ticks_used - Process.get(:ticks_remaining)
        new_task = %{task | ticks_used: task.ticks_used + ticks_used}
        {:ok, value, new_task}

      :quota_exceeded ->
        new_task = %{task | ticks_used: task.tick_quota}
        {:quota_exceeded, new_task}

      {:error, reason} ->
        {:error, reason, task}
    end
  end

  defp execute_statements(statements, env) do
    execute_statements_loop(statements, env)
  end

  defp execute_statements_loop([], env) do
    # No statements, return 0
    {Value.num(0), env}
  end

  defp execute_statements_loop([stmt], env) do
    # Last statement - return its value and env
    case Interpreter.eval(stmt, env) do
      {:ok, value, new_env} -> {value, new_env}
      {:error, err} -> throw({:error, err})
    end
  end

  defp execute_statements_loop([stmt | rest], env) do
    # Not last statement - continue with updated env
    case Interpreter.eval(stmt, env) do
      {:ok, _value, new_env} -> execute_statements_loop(rest, new_env)
      {:error, err} -> throw({:error, err})
    end
  end

  ## Task Registry Helpers

  @doc "List all running tasks"
  def list_tasks do
    Registry.select(Alchemoo.TaskRegistry, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
    ])
  end

  defp maybe_log_task_debug(message) do
    if Application.get_env(:alchemoo, :trace_tasks, false) do
      Logger.debug(message)
    end
  end

  @doc "List tasks for a specific player"
  def list_player_tasks(player_id) do
    Registry.select(Alchemoo.TaskRegistry, [
      {{:"$1", :"$2", %{player: player_id}}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc "Kill all tasks for a player"
  def kill_player_tasks(player_id) do
    list_player_tasks(player_id)
    |> Enum.each(fn {_task_id, pid} ->
      GenServer.stop(pid, :normal)
    end)
  end

  @doc "Count tasks for a player"
  def count_player_tasks(player_id) do
    length(list_player_tasks(player_id))
  end
end
