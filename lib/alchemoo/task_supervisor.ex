defmodule Alchemoo.TaskSupervisor do
  @moduledoc """
  Dynamic supervisor for MOO task processes. Spawns and monitors tasks,
  enforces task limits, and handles task crashes.
  """
  use DynamicSupervisor

  # CONFIG: Should be extracted to config
  # CONFIG: :alchemoo, :max_total_tasks
  @max_tasks 1000

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_children: @max_tasks
    )
  end

  @doc "Spawn a new task"
  def spawn_task(verb_code, env, opts \\ []) do
    # Check task limit
    case count_tasks() >= @max_tasks do
      true ->
        {:error, :too_many_tasks}

      false ->
        task_opts = Keyword.merge([verb_code: verb_code, env: env], opts)
        spec = {Alchemoo.Task, task_opts}
        DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end

  @doc "Kill a task by PID"
  def kill_task(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc "Count running tasks"
  def count_tasks do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc "List all task PIDs"
  def list_tasks do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end
end
