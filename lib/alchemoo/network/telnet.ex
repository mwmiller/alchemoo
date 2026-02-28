defmodule Alchemoo.Network.Telnet do
  @moduledoc """
  Telnet server using Ranch. Accepts TCP connections and hands them off
  to Connection.Handler processes.
  """
  require Logger

  defp default_port do
    config = Application.get_env(:alchemoo, :network, [])
    (config[:telnet] && config[:telnet][:port]) || 7777
  end

  defp max_connections, do: Application.get_env(:alchemoo, :max_connections, 1000)

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc "Start the Telnet listener"
  def start_link(opts \\ []) do
    port =
      case Keyword.get(opts, :port, default_port()) do
        fun when is_function(fun, 0) -> fun.()
        val -> val
      end

    ranch_opts = %{
      socket_opts: [port: port],
      max_connections: max_connections(),
      num_acceptors: 10
    }

    case :ranch.start_listener(
           :alchemoo_telnet,
           :ranch_tcp,
           ranch_opts,
           __MODULE__,
           []
         ) do
      {:ok, pid} ->
        case :ranch.get_addr(:alchemoo_telnet) do
          {_ip, actual_port} ->
            Logger.info("Telnet server listening on port #{actual_port}")

          _ ->
            Logger.info("Telnet server listening on port #{port}")
        end

        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Telnet server: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Stop the Telnet listener"
  def stop do
    :ranch.stop_listener(:alchemoo_telnet)
  end

  @doc "Get listener info"
  def info do
    case :ranch.get_addr(:alchemoo_telnet) do
      {ip, port} ->
        %{
          ip: :inet.ntoa(ip) |> to_string(),
          port: port,
          connections: :ranch.procs(:alchemoo_telnet, :connections) |> length()
        }

      error ->
        error
    end
  end

  ## Ranch Protocol Callbacks

  @doc false
  def start_link(ref, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [ref, transport, opts])
    {:ok, pid}
  end

  @doc false
  def init(ref, transport, _opts) do
    {:ok, socket} = :ranch.handshake(ref)

    # Start connection handler
    case Alchemoo.Connection.Supervisor.start_connection(socket, transport) do
      {:ok, handler_pid} ->
        # Transfer socket control to handler
        :ok = transport.controlling_process(socket, handler_pid)

        # Enable active mode for handler
        :ok = transport.setopts(socket, [{:active, true}])

        # Keep this process alive to satisfy Ranch
        :timer.sleep(:infinity)

      {:error, reason} ->
        Logger.error("Failed to start connection handler: #{inspect(reason)}")
        transport.close(socket)
    end
  end
end
