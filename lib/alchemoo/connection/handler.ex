defmodule Alchemoo.Connection.Handler do
  @moduledoc """
  Connection Handler manages a single player connection. It handles input
  buffering, output queuing, command processing, and task spawning.
  """
  use GenServer, restart: :temporary
  require Logger

  alias Alchemoo.Command.Executor
  alias Alchemoo.Connection.Supervisor, as: ConnSupervisor
  alias Alchemoo.Database.Resolver
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Database.Verb
  alias Alchemoo.Task
  alias Alchemoo.TaskSupervisor
  alias Alchemoo.Value
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
    output_delimiters: ["", ""],
    peer_info: "unknown",
    connection_options: %{
      "binary" => 0,
      "hold-input" => 0,
      "client-echo" => 1,
      "flush-command" => ".flush",
      "output-delimiters" => ["", ""]
    },
    waiting_tasks: [],
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

  @doc "Request next line of input for a task"
  def request_input(pid, task_pid) do
    GenServer.cast(pid, {:request_input, task_pid})
  end

  @doc "Clear all waiting tasks for input"
  def flush_input(pid) do
    GenServer.cast(pid, :flush_input)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    socket = Keyword.fetch!(opts, :socket)
    transport = Keyword.get(opts, :transport, :ranch_tcp)

    case transport.peername(socket) do
      {:ok, {ip, port}} ->
        peer_info = "#{:inet.ntoa(ip)}:#{port}"

        conn = %__MODULE__{
          socket: socket,
          transport: transport,
          connected_at: System.system_time(:second),
          last_activity: System.system_time(:second),
          peer_info: peer_info
        }

        # Send welcome message
        send_text(conn, welcome_message())

        Logger.info("New connection from #{peer_info}")

        {:ok, conn}

      {:error, _reason} ->
        # Socket is already closed or invalid, stop initialization
        {:stop, :normal}
    end
  end

  @impl true
  def handle_cast({:output, text}, conn) do
    [prefix, suffix] = conn.output_delimiters
    wrapped_text = prefix <> text <> suffix
    new_conn = queue_output(conn, wrapped_text)
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
  def handle_cast({:set_output_delimiters, delimiters}, conn) do
    # Synchronize with connection_options
    new_options = Map.put(conn.connection_options, "output-delimiters", delimiters)
    {:noreply, %{conn | output_delimiters: delimiters, connection_options: new_options}}
  end

  @impl true
  def handle_cast({:set_connection_option, name, value}, conn) do
    new_options = Map.put(conn.connection_options, name, value)

    # Special handling for certain options
    new_conn =
      case name do
        "output-delimiters" ->
          case value do
            [prefix, suffix] -> %{conn | output_delimiters: [prefix, suffix]}
            _ -> conn
          end

        _ ->
          conn
      end

    {:noreply, %{new_conn | connection_options: new_options}}
  end

  @impl true
  def handle_cast({:request_input, task_pid}, conn) do
    {:noreply, %{conn | waiting_tasks: conn.waiting_tasks ++ [task_pid]}}
  end

  @impl true
  def handle_cast(:flush_input, conn) do
    Enum.each(conn.waiting_tasks, fn pid ->
      send(pid, {:input_received, ""})
    end)

    {:noreply, %{conn | waiting_tasks: []}}
  end

  @impl true
  def handle_call(:info, _from, conn) do
    info = %{
      player_id: conn.player_id,
      connected_at: conn.connected_at,
      last_activity: conn.last_activity,
      idle_seconds: System.system_time(:second) - conn.last_activity,
      state: conn.state,
      output_queue_length: Enum.reduce(conn.output_queue, 0, &(&2 + String.length(&1))),
      output_delimiters: conn.output_delimiters,
      peer_info: conn.peer_info
    }

    {:reply, info, conn}
  end

  @impl true
  def handle_call(:get_output_delimiters, _from, conn) do
    {:reply, conn.output_delimiters, conn}
  end

  @impl true
  def handle_call(:get_connection_options, _from, conn) do
    {:reply, Map.keys(conn.connection_options), conn}
  end

  @impl true
  def handle_call({:get_connection_option, name}, _from, conn) do
    {:reply, Map.get(conn.connection_options, name), conn}
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

    db_welcome || Version.banner(moo_name()) <> "\n"
  end

  defp moo_name do
    # Try common locations for MOO name
    # 1. #0.moo_name
    # 2. $network.moo_name
    # 3. Config fallback
    case DB.get_property(0, "moo_name") do
      {:ok, {:str, name}} ->
        name

      _ ->
        network_id = Resolver.object(:network)

        case DB.get_property(network_id, "moo_name") do
          {:ok, {:str, name}} -> name
          _ -> Application.get_env(:alchemoo, :moo_name, "Alchemoo")
        end
    end
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

    case conn.waiting_tasks do
      [task_pid | rest] ->
        # Send input to waiting task
        send(task_pid, {:input_received, line})
        %{conn | waiting_tasks: rest}

      [] ->
        case conn.state do
          :connected ->
            # Not logged in yet
            process_login_command(conn, line)

          :logged_in ->
            # Logged in, process as MOO command
            process_moo_command(conn, line)
        end
    end
  end

  defp process_login_command(conn, line) do
    case String.split(line, " ", trim: true) do
      [cmd | args] ->
        dispatch_login_command(conn, cmd, args)

      [] ->
        conn
    end
  end

  defp dispatch_login_command(conn, cmd, args) do
    cond do
      match_cmd?(cmd, "co*nnect") -> handle_login_connect(conn, args)
      match_cmd?(cmd, "cr*eate") -> handle_login_create(conn, args)
      match_cmd?(cmd, "q*uit") -> handle_login_quit(conn)
      match_cmd?(cmd, "w*ho") -> handle_login_who(conn)
      true -> dispatch_login_meta_command(conn, cmd)
    end
  end

  defp dispatch_login_meta_command(conn, cmd) do
    cond do
      match_cmd?(cmd, "up*time") ->
        handle_login_uptime(conn)

      match_cmd?(cmd, "v*ersion") ->
        handle_login_version(conn)

      match_cmd?(cmd, "h*elp") ->
        handle_login_help(conn)

      match_cmd?(cmd, "wel*come") ->
        handle_login_welcome(conn)

      true ->
        send_text(conn, "I don't understand that. Type 'help' for available commands.\n")
        conn
    end
  end

  defp match_cmd?(input, pattern) do
    Verb.match_pattern?(pattern, String.downcase(input))
  end

  defp handle_login_connect(conn, [name]) do
    Logger.debug("Attempting login for '#{name}' (no password)")
    handle_login_connect(conn, [name, ""])
  end

  defp handle_login_connect(conn, [name, password | _]) do
    Logger.debug("Attempting login for '#{name}'")

    case Alchemoo.Auth.login(name, password) do
      {:ok, player_id} ->
        Logger.info("Player '#{name}' (##{player_id}) logged in successfully")
        send_text(conn, "*** Connected as #{name} ***\n")

        # Notify database
        Logger.debug("Triggering user_connected hook for ##{player_id}")
        notify_db_connected(player_id)

        %{conn | state: :logged_in, player_id: player_id}

      {:error, :not_found} ->
        Logger.debug("Login failed: player '#{name}' not found")
        send_text(conn, "Invalid player name: #{name}\n")
        conn

      {:error, :invalid_password} ->
        Logger.debug("Login failed: invalid password for '#{name}'")
        send_text(conn, "Invalid password for player: #{name}\n")
        conn
    end
  end

  defp handle_login_connect(conn, _) do
    send_text(conn, "Usage: connect <name> <password>\n")
    conn
  end

  defp handle_login_create(conn, [name, password | _]) do
    Logger.debug("Attempting to create player '#{name}'")

    case Alchemoo.Auth.create_player(name, password) do
      {:ok, player_id} ->
        Logger.info("Player '#{name}' (##{player_id}) created successfully")
        send_text(conn, "*** Created player #{name} ***\n")

        # Notify database of creation
        Logger.debug("Triggering user_created hook for ##{player_id}")
        notify_db_created(player_id)

        # Do NOT auto-login, let user use 'connect' as per example
        conn

      {:error, reason} ->
        Logger.error("Failed to create player '#{name}': #{inspect(reason)}")
        send_text(conn, "Failed to create player: #{inspect(reason)}\n")
        conn
    end
  end

  defp handle_login_create(conn, _) do
    send_text(conn, "Usage: create <name> <password>\n")
    conn
  end

  defp notify_db_connected(player_id) do
    spawn_system_task("user_connected", [Value.obj(player_id)])
  end

  defp notify_db_created(player_id) do
    spawn_system_task("user_created", [Value.obj(player_id)])
  end

  defp spawn_system_task(verb_name, args) do
    Logger.debug("Searching for system verb #0:#{verb_name}")
    # Try to find and call the verb on #0
    case DB.find_verb(0, verb_name) do
      {:ok, 0, verb} ->
        Logger.debug("Found verb #0:#{verb_name}, spawning task")
        # Get database snapshot for runtime
        runtime = Alchemoo.Runtime.new(DB.get_snapshot())

        env = %{
          :runtime => runtime,
          "player" => hd(args),
          "this" => Value.obj(0),
          "caller" => Value.obj(-1),
          "verb" => Value.str(verb_name),
          "args" => Value.list(args),
          "argstr" => Value.str(""),
          "dobj" => Value.obj(-1),
          "dobjstr" => Value.str(""),
          "prepstr" => Value.str(""),
          "iobj" => Value.obj(-1),
          "iobjstr" => Value.str("")
        }

        task_opts = [
          player: 2,
          this: 0,
          caller: -1,
          args: args,
          handler_pid: self(),
          verb_name: verb_name
        ]

        code = Enum.join(verb.code, "\n")

        case TaskSupervisor.spawn_task(code, env, task_opts) do
          {:ok, pid} ->
            Logger.debug("System task for #0:#{verb_name} spawned with PID #{inspect(pid)}")
            {:ok, pid}

          error ->
            Logger.error("Failed to spawn system task #0:#{verb_name}: #{inspect(error)}")
            error
        end

      other ->
        Logger.debug("System verb #0:#{verb_name} not found or error: #{inspect(other)}")
        :ok
    end
  end

  defp handle_login_quit(conn) do
    send_text(conn, "Goodbye!\n")
    GenServer.cast(self(), :close)
    conn
  end

  defp handle_login_who(conn) do
    connections = ConnSupervisor.list_connections()
    logged_in = list_logged_in_players(connections, conn)

    send_text(conn, "Currently connected players:\n")

    if Enum.empty?(logged_in) do
      send_text(conn, "  None\n")
    else
      Enum.each(logged_in, fn line -> send_text(conn, "  #{line}\n") end)
    end

    send_text(
      conn,
      "Total: #{length(logged_in)} logged-in, #{length(connections)} total connections\n"
    )

    conn
  end

  defp list_logged_in_players(connections, current_conn) do
    Enum.flat_map(connections, fn pid -> get_info_from_pid(pid, current_conn) end)
  end

  defp get_info_from_pid(pid, current_conn) do
    info = if pid == self(), do: build_info(current_conn), else: info(pid)
    extract_logged_in_info(info)
  end

  defp build_info(conn) do
    %{
      player_id: conn.player_id,
      connected_at: conn.connected_at,
      last_activity: conn.last_activity,
      idle_seconds: System.system_time(:second) - conn.last_activity,
      state: conn.state,
      output_queue_length: Enum.reduce(conn.output_queue, 0, &(&2 + String.length(&1))),
      output_delimiters: conn.output_delimiters,
      peer_info: conn.peer_info
    }
  end

  defp extract_logged_in_info(%{player_id: id, state: :logged_in}) when id != nil do
    name =
      case DB.get_property(id, "name") do
        {:ok, {:str, n}} -> n
        _ -> "Player ##{id}"
      end

    ["#{name} (##{id})"]
  end

  defp extract_logged_in_info(_), do: []

  defp handle_login_uptime(conn) do
    {:num, start_time} = Alchemoo.Builtins.call(:server_started, [])
    uptime = System.system_time(:second) - start_time
    send_text(conn, "Server uptime: #{uptime} seconds\n")
    conn
  end

  defp handle_login_version(conn) do
    send_text(conn, "Alchemoo v#{Version.version()}\n")
    conn
  end

  defp handle_login_welcome(conn) do
    send_text(conn, welcome_message())
    conn
  end

  defp handle_login_help(conn) do
    send_text(conn, "Available commands:\n")
    send_text(conn, "  connect <name> <password> - Log in as an existing player\n")
    send_text(conn, "  create <name> <password>  - Create a new player\n")
    send_text(conn, "  who                       - List connected players\n")
    send_text(conn, "  quit                      - Disconnect\n")
    send_text(conn, "  uptime                    - Show server uptime\n")
    send_text(conn, "  version                   - Show server version\n")
    send_text(conn, "  welcome                   - Show welcome banner\n")
    conn
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
