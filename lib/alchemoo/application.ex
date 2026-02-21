defmodule Alchemoo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Alchemoo v#{Alchemoo.Version.version()}...")

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
        Logger.info("Alchemoo started successfully")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Alchemoo: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Alchemoo shutting down...")
    :ok
  end
end
