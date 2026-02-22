defmodule Alchemoo.Connection.Handler do
  @moduledoc """
  Connection Handler manages a single player connection. It handles input
  buffering, output queuing, command processing, and task spawning.
  """
  use GenServer
  require Logger

  alias Alchemoo.Command.Executor
  alias Alchemoo.Database.Resolver
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Task
  alias Alchemoo.TaskSupervisor
  alias Alchemoo.Version

  # CONFIG: Should be extracted to config
  # CONFIG: :alchemoo, :max_output_queue
  @max_output_queue 1000

  defstruct [
    :socket,
    :transport,
    :player_id,
    :connected_at,
    :last_activity,
    input_buffer: "",
    output_queue: [],
    state: :connected
  ]

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Send output to the connection"
  def send_output(pid, text) when is_binary(text) do
    GenServer.cast(pid, {:output, text})
  end

  @doc "Get connection info"
  def info(pid) do
    GenServer.call(pid, :info)
  end

  @doc "Close connection"
  def close(pid) do
    GenServer.cast(pid, :close)
  end

  @doc "Force input into the connection"
  def input(pid, text) when is_binary(text) do
    GenServer.cast(pid, {:input, text})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    socket = Keyword.fetch!(opts, :socket)
    transport = Keyword.get(opts, :transport, :ranch_tcp)

    conn = %__MODULE__{
      socket: socket,
      transport: transport,
      connected_at: System.system_time(:second),
      last_activity: System.system_time(:second)
    }

    # Send welcome message
    send_text(conn, welcome_message())

    peer_info =
      case :inet.peername(socket) do
        {:ok, {ip, port}} -> "#{:inet.ntoa(ip)}:#{port}"
        _ -> "unknown"
      end

    Logger.info("New connection from #{peer_info}")

    {:ok, conn}
  end

  @impl true
  def handle_cast({:output, text}, conn) do
    new_conn = queue_output(conn, text)
    {:noreply, new_conn}
  end

  @impl true
  def handle_cast(:close, conn) do
    {:stop, :normal, conn}
  end

  @impl true
  def handle_cast({:input, text}, conn) do
    # Process forced input as if it came from the socket
    new_conn = process_input(conn, text)
    {:noreply, new_conn}
  end

  @impl true
  def handle_call(:info, _from, conn) do
    info = %{
      player_id: conn.player_id,
      connected_at: conn.connected_at,
      last_activity: conn.last_activity,
      idle_seconds: System.system_time(:second) - conn.last_activity,
      state: conn.state,
      output_queue_length: Enum.reduce(conn.output_queue, 0, &(&2 + String.length(&1)))
    }

    {:reply, info, conn}
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = conn) do
    # Update activity time
    conn = %{conn | last_activity: System.system_time(:second)}

    # Add to input buffer
    new_buffer = conn.input_buffer <> data

    # Process complete lines
    {lines, remaining} = extract_lines(new_buffer)

    # Process each line
    new_conn =
      Enum.reduce(lines, conn, fn line, acc ->
        process_input(acc, line)
      end)

    {:noreply, %{new_conn | input_buffer: remaining}}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %{socket: socket} = conn) do
    case conn.player_id do
      nil ->
        Logger.info("Connection closed (not logged in)")

      player_id ->
        player_name = get_player_name(player_id)
        Logger.info("Player #{player_name} disconnected")
        # Kill all tasks for this player
        Task.kill_player_tasks(player_id)
    end

    {:stop, :normal, conn}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = conn) do
    Logger.error("Connection error: #{inspect(reason)}")
    {:stop, :normal, conn}
  end

  @impl true
  def handle_info({:task_output, text}, conn) do
    # Output from a task
    new_conn = queue_output(conn, text)
    {:noreply, new_conn}
  end

  ## Private Helpers

  defp welcome_message do
    login_id = Resolver.object(:login)

    db_welcome =
      case DB.get_property(login_id, "welcome_message") do
        {:ok, value} -> format_welcome_value(value)
        _ -> nil
      end

    db_welcome || Version.banner() <> "\n"
  end

  defp format_welcome_value({:str, msg}) when is_binary(msg) and msg != "", do: msg <> "\n"

  defp format_welcome_value({:list, items}) do
    items
    |> Enum.map_join("\n", fn
      {:str, s} -> s
      v -> Alchemoo.Value.to_literal(v)
    end)
    |> Kernel.<>("\n")
  end

  defp format_welcome_value(_), do: nil

  defp extract_lines(buffer) do
    lines = String.split(buffer, ["\n", "\r\n", "\r"], trim: true)

    # Check if buffer ends with newline
    case String.ends_with?(buffer, ["\n", "\r\n", "\r"]) do
      true ->
        {lines, ""}

      false ->
        # Last line is incomplete
        case lines do
          [] -> {[], buffer}
          [_ | _] -> {Enum.slice(lines, 0..-2//1), List.last(lines)}
        end
    end
  end

  defp process_input(conn, line) do
    line = String.trim(line)

    case conn.state do
      :connected ->
        # Not logged in yet
        process_login_command(conn, line)

      :logged_in ->
        # Logged in, process as MOO command
        process_moo_command(conn, line)
    end
  end

  defp process_login_command(conn, line) do
    case String.split(line, " ", parts: 3) do
      ["connect", name, _password] ->
        # TODO: Implement actual authentication
        # For now, just create/login as wizard
        Logger.info("Player '#{name}' logged in")
        send_text(conn, "*** Connected as #{name} ***\n")
        # Wizard
        %{conn | state: :logged_in, player_id: 2}

      ["create", name, _password] ->
        # TODO: Implement player creation
        Logger.info("Player '#{name}' created")
        send_text(conn, "*** Created player #{name} ***\n")
        %{conn | state: :logged_in, player_id: 2}

      _ ->
        send_text(conn, "Invalid command. Use: connect <name> <password>\n")
        conn
    end
  end

  defp process_moo_command(conn, line) do
    # Built-in commands
    case line do
      "quit" ->
        send_text(conn, "Goodbye!\n")
        GenServer.cast(self(), :close)
        conn

      "@who" ->
        # List connected players
        send_text(conn, "Connected players:\n")
        send_text(conn, "  You\n")
        conn

      "@stats" ->
        # Show stats
        stats = DB.stats()
        send_text(conn, "Database: #{stats.object_count} objects\n")
        send_text(conn, "Tasks: #{TaskSupervisor.count_tasks()}\n")
        conn

      "" ->
        # Empty line
        conn

      _ ->
        # Execute as MOO command
        execute_moo_command(conn, line)
    end
  end

  defp execute_moo_command(conn, line) do
    # Use command executor to parse and execute
    Executor.execute(line, conn.player_id, self())
    # Task spawned (or error sent), either way continue

    conn
  end

  defp queue_output(conn, text) do
    case length(conn.output_queue) >= @max_output_queue do
      true ->
        Logger.warning("Output queue full, dropping message")
        conn

      false ->
        new_queue = conn.output_queue ++ [text]

        # Try to flush immediately
        flush_output(%{conn | output_queue: new_queue})
    end
  end

  defp flush_output(conn) do
    case conn.output_queue do
      [] ->
        conn

      [text | rest] ->
        case send_text(conn, text) do
          :ok ->
            flush_output(%{conn | output_queue: rest})

          {:error, _} ->
            # Keep in queue, will retry later
            conn
        end
    end
  end

  defp send_text(conn, text) do
    case conn.transport.send(conn.socket, text) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_player_name(player_id) do
    case DB.get_property(player_id, "name") do
      {:ok, {:str, name}} -> "'#{name}'"
      _ -> "##{player_id}"
    end
  end
end
