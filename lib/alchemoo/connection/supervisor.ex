defmodule Alchemoo.Connection.Supervisor do
  @moduledoc """
  Dynamic supervisor for connection handler processes.
  """
  use DynamicSupervisor
  require Logger

  defp max_connections, do: Application.get_env(:alchemoo, :max_connections, 1000)

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_children: max_connections()
    )
  end

  @doc "Start a new connection handler"
  def start_connection(socket, transport \\ :ranch_tcp, opts \\ []) do
    case count_connections() >= max_connections() do
      true ->
        {:error, :too_many_connections}

      false ->
        handler_opts = [socket: socket, transport: transport] ++ opts
        spec = {Alchemoo.Connection.Handler, handler_opts}
        DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end

  @doc "Count active connections"
  def count_connections do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc "List all connection PIDs"
  def list_connections do
    children = DynamicSupervisor.which_children(__MODULE__)

    if trace_connections?() do
      Logger.debug("Supervisor children: #{inspect(children)}")
    end

    children
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end

  defp trace_connections?, do: Application.get_env(:alchemoo, :trace_connections, false)
end
