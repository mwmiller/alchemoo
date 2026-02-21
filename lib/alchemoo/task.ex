defmodule Alchemoo.Task do
  @moduledoc """
  A Task represents a single MOO task execution. Each task runs in its own
  GenServer process with tick quota enforcement, suspend/resume support,
  and crash isolation.
  """
  use GenServer
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
    ticks_used: 0,
    tick_quota: @default_tick_quota,
    suspended_until: nil,
    result: nil
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
    task = %__MODULE__{
      id: make_ref(),
      verb_code: Keyword.fetch!(opts, :verb_code),
      env: Keyword.get(opts, :env, %{}),
      player: Keyword.get(opts, :player),
      this: Keyword.get(opts, :this),
      caller: Keyword.get(opts, :caller),
      args: Keyword.get(opts, :args, []),
      handler_pid: Keyword.get(opts, :handler_pid),
      sync_caller: Keyword.get(opts, :sync_caller),
      tick_quota: Keyword.get(opts, :tick_quota, @default_tick_quota)
    }

    # Registry allows metadata-based lookups (e.g. all tasks for a player)
    Registry.register(Alchemoo.TaskRegistry, task.id, %{
      player: task.player,
      this: task.this,
      caller: task.caller,
      handler_pid: task.handler_pid,
      started_at: System.system_time(:second)
    })

    # Process dictionary provides local context for built-in function execution
    Process.put(:task_context, %{
      player: task.player,
      this: task.this,
      caller: task.caller,
      handler_pid: task.handler_pid
    })

    {:ok, task, {:continue, :execute}}
  end

  @impl true
  def handle_continue(:execute, task) do
    case execute_with_quota(task) do
      {:ok, result, new_task} ->
        handle_task_success(result, new_task)

      {:suspended, new_task} ->
        {:noreply, new_task}

      {:quota_exceeded, new_task} ->
        handle_task_quota_exceeded(new_task)

      {:error, reason, new_task} ->
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

  @impl true
  def handle_info(:resume, task) do
    # Resume from suspend
    {:noreply, task, {:continue, :execute}}
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
      result = execute_statements(ast.statements, task.env)

      ticks_used = task.tick_quota - task.ticks_used - Process.get(:ticks_remaining)
      new_task = %{task | ticks_used: task.ticks_used + ticks_used}
      {:ok, result, new_task}
    catch
      {:return, value} ->
        ticks_used = task.tick_quota - task.ticks_used - Process.get(:ticks_remaining)
        new_task = %{task | ticks_used: task.ticks_used + ticks_used}
        {:ok, value, new_task}

      :quota_exceeded ->
        new_task = %{task | ticks_used: task.tick_quota}
        {:quota_exceeded, new_task}

      {:suspend, seconds} ->
        ticks_used = task.tick_quota - task.ticks_used - Process.get(:ticks_remaining)
        new_task = %{task | ticks_used: task.ticks_used + ticks_used}
        Process.send_after(self(), :resume, seconds * 1000)
        {:suspended, new_task}

      {:error, reason} ->
        {:error, reason, task}
    end
  end

  defp execute_statements(statements, env) do
    execute_statements_loop(statements, env)
  end

  defp execute_statements_loop([], _env) do
    # No statements, return 0
    Value.num(0)
  end

  defp execute_statements_loop([stmt], env) do
    # Last statement - return its value
    case Interpreter.eval(stmt, env) do
      {:ok, value, _new_env} -> value
      {:ok, value} -> value
      {:error, err} -> throw({:error, err})
    end
  end

  defp execute_statements_loop([stmt | rest], env) do
    # Not last statement - continue
    case Interpreter.eval(stmt, env) do
      {:ok, _value, new_env} -> execute_statements_loop(rest, new_env)
      {:ok, _value} -> execute_statements_loop(rest, env)
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
