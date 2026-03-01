defmodule Alchemoo.Network.WebSocket do
  @moduledoc """
  WebSocket listener using Bandit and WebSock.
  Bridges WebSocket connections to Connection.Handler.
  """
  require Logger

  # Behavior for WebSock
  @behaviour WebSock

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  defp default_port do
    config = Application.get_env(:alchemoo, :network, [])
    (config[:websocket] && config[:websocket][:port]) || 4444
  end

  @doc "Start the WebSocket listener"
  def start_link(opts \\ []) do
    port =
      case Keyword.get(opts, :port, default_port()) do
        fun when is_function(fun, 0) -> fun.()
        val -> val
      end

    case Bandit.start_link(
           plug: __MODULE__.Plug,
           port: port,
           scheme: :http
         ) do
      {:ok, pid} ->
        case info(pid) do
          %{port: actual_port} ->
            Logger.info("WebSocket server listening on port #{actual_port}")

          _ ->
            Logger.info("WebSocket server listening on port #{port}")
        end

        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start WebSocket server: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Get listener info"
  def info(pid \\ nil) do
    # Bandit uses ThousandIsland underneath.
    # We can get info from ThousandIsland.listener_info
    # When starting Bandit, it starts a ThousandIsland listener.
    # The pid returned by Bandit.start_link is the ThousandIsland supervisor.
    
    target_pid = pid || Process.whereis(__MODULE__)

    if target_pid do
      # Note: Bandit doesn't have a direct info/0 but we can reach into ThousandIsland
      # In Bandit 1.x, we can find the ThousandIsland listener
      case ThousandIsland.listener_info(target_pid) do
        {:ok, {address, port}} ->
          %{
            port: port,
            address: address,
            connections: 0
          }
        _ ->
          %{port: :unknown}
      end
    else
      %{port: :unknown}
    end
  end

  ## WebSock Callbacks

  @impl true
  def init(opts) do
    # Start the Alchemoo Connection.Handler
    # We use 'self()' as the 'socket' because we are the process
    # that will receive messages from the handler.
    case Alchemoo.Connection.Supervisor.start_connection(self(), __MODULE__) do
      {:ok, handler_pid} ->
        # Store handler PID in state
        {:ok, %{handler: handler_pid, peer: opts[:peer]}}

      {:error, reason} ->
        Logger.error("Failed to start connection handler for WebSocket: #{inspect(reason)}")
        {:stop, :handler_start_failed}
    end
  end

  @impl true
  def handle_in({data, [opcode: :text]}, state) do
    # Forward text data to handler
    # We add a newline because MOO commands expect it,
    # but the browser typically sends the line without it.
    Kernel.send(state.handler, {:network_input, data <> "\n"})
    {:ok, state}
  end

  @impl true
  def handle_in({data, [opcode: :binary]}, state) do
    # Forward binary data to handler
    Kernel.send(state.handler, {:network_input, data})
    {:ok, state}
  end

  @impl true
  def handle_info({:output, text}, state) do
    # Forward output from handler to WebSocket client
    # WebSockets handle their own line endings, but we should probably
    # normalize to \n or just send as-is depending on client preference.
    # For now, we'll strip the \r if it exists since many web clients prefer \n.
    clean_text = String.replace(text, "\r\n", "\n")
    {:push, {:text, clean_text}, state}
  end

  @impl true
  def handle_info({:network_output, text}, state) do
    # Handle the normalized message name if we use it consistently
    {:push, {:text, text}, state}
  end

  @impl true
  def handle_info({:network_closed, _reason}, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:EXIT, pid, _reason}, %{handler: pid} = state) do
    # Handler died, close the WebSocket
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  ## Transport Interface for Connection.Handler

  @doc "Send data to the WebSocket client"
  def send(pid, data) do
    # This is called by Connection.Handler via transport.send(socket, data)
    # Since 'socket' is the WebSocket process (self() in init), we just send a message to it.
    Kernel.send(pid, {:output, data})
    :ok
  end

  @doc "Close the WebSocket connection"
  def close(pid) do
    Kernel.send(pid, {:network_closed, :normal})
    :ok
  end

  @doc "Get peer info"
  def peername(_pid) do
    # In a real implementation, we'd pull this from the Plug.Conn
    {:ok, {{127, 0, 0, 1}, 0}}
  end

  # Dummy functions to satisfy the transport interface used by Connection.Handler
  def setopts(_socket, _opts), do: :ok
  def controlling_process(_socket, _pid), do: :ok

  def use_readline?, do: true
  def default_echo?, do: false

  def preprocess(data, conn), do: {data, conn}

  ## Internal Plug for Bandit

  defmodule Plug do
    @moduledoc false
    def init(opts), do: opts

    def call(conn, _opts) do
      # Upgrade to WebSocket
      conn
      |> WebSockAdapter.upgrade(Alchemoo.Network.WebSocket, [], timeout: 60_000)
      |> (fn c -> Elixir.Plug.Conn.halt(c) end).()
    end
  end
end
