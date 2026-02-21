defmodule Alchemoo.Connection.Supervisor do
  @moduledoc """
  Dynamic supervisor for connection handler processes.
  """
  use DynamicSupervisor

  # CONFIG: Should be extracted to config
  # CONFIG: :alchemoo, :max_connections
  @max_connections 1000

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_children: @max_connections
    )
  end

  @doc "Start a new connection handler"
  def start_connection(socket, transport \\ :ranch_tcp) do
    case count_connections() >= @max_connections do
      true ->
        {:error, :too_many_connections}

      false ->
        spec = {Alchemoo.Connection.Handler, socket: socket, transport: transport}
        DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end

  @doc "Count active connections"
  def count_connections do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc "List all connection PIDs"
  def list_connections do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end
end
