defmodule Alchemoo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Runtime
  alias Alchemoo.TaskSupervisor
  alias Alchemoo.Value

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Alchemoo v#{Alchemoo.Version.version()}...")

    with :ok <- ensure_base_dir() do
      start_supervisor()
    end
  end

  defp start_supervisor do
    children = [
      {Alchemoo.Database.Server, []},
      {Registry, keys: :unique, name: Alchemoo.TaskRegistry},
      Alchemoo.TaskSupervisor,
      Alchemoo.Connection.Supervisor,
      {Alchemoo.Checkpoint.Server, []},
      {Alchemoo.Network.Supervisor, [config: Alchemoo.Network.Supervisor.config()]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Alchemoo.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Task.start(fn -> run_startup_verb(0, "server_started") end)

        Logger.info("Alchemoo started successfully")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Alchemoo: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_base_dir do
    case Application.get_env(:alchemoo, :base_dir) do
      path when is_binary(path) ->
        case File.mkdir_p(path) do
          :ok -> :ok
          {:error, reason} -> {:error, {:base_dir_create_failed, path, reason}}
        end

      _ ->
        :ok
    end
  end

  defp run_startup_verb(obj_id, verb_name) do
    case DB.find_verb(obj_id, verb_name) do
      {:ok, ^obj_id, verb} ->
        runtime = Runtime.new(DB.get_snapshot())

        env = %{
          :runtime => runtime,
          "player" => Value.obj(2),
          "this" => Value.obj(obj_id),
          "caller" => Value.obj(-1),
          "verb" => Value.str(verb_name),
          "args" => Value.list([])
        }

        task_opts = [
          player: 2,
          this: obj_id,
          caller: -1,
          perms: 2,
          caller_perms: 2,
          args: [],
          verb_name: verb_name
        ]

        code = Enum.join(verb.code, "\n")

        case TaskSupervisor.spawn_task(code, env, task_opts) do
          {:ok, _pid} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to spawn startup verb #{verb_name}: #{inspect(reason)}")
        end

      _ ->
        Logger.warning("Startup verb ##{obj_id}:#{verb_name} not found")
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Alchemoo shutting down...")
    :ok
  end
end
