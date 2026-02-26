defmodule Alchemoo.Connection.Handler do
  @moduledoc """
  Connection Handler manages a single player connection.
  Delegates un-logged-in input to #0:do_login_command.
  """
  use GenServer, restart: :temporary
  require Logger

  alias Alchemoo.Command.Executor
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Task, as: MOOTask
  alias Alchemoo.TaskSupervisor
  alias Alchemoo.Value

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
    active_task: nil,
    state: :connected
  ]

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def send_output(pid, text) when is_binary(text) do
    GenServer.cast(pid, {:output, text})
  end

  def info(pid) do
    GenServer.call(pid, :info)
  end

  def close(pid) do
    GenServer.cast(pid, :close)
  end

  def input(pid, text) when is_binary(text) do
    GenServer.cast(pid, {:input, text})
  end

  def request_input(pid, task_pid) do
    GenServer.cast(pid, {:request_input, task_pid})
  end

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
        # Unique negative ID for un-logged-in connections
        conn_id = -(1000 + :erlang.phash2(make_ref()))

        conn = %__MODULE__{
          socket: socket,
          transport: transport,
          connected_at: System.system_time(:second),
          last_activity: System.system_time(:second),
          peer_info: peer_info,
          player_id: conn_id
        }

        Logger.info("New connection from #{peer_info} assigned ID #{conn_id}")

        {:ok, conn, {:continue, :initial_login}}

      {:error, _reason} ->
        {:stop, :normal}
    end
  end

  @impl true
  def handle_continue(:initial_login, conn) do
    # Trigger initial null do_login_command (no arguments)
    new_conn = run_login_task(conn, "", [])
    {:noreply, new_conn}
  end

  @impl true
  def handle_cast({:output, text}, conn) do
    [prefix, suffix] = conn.output_delimiters
    new_conn = queue_output(conn, prefix <> text <> suffix)
    {:noreply, new_conn}
  end

  @impl true
  def handle_cast(:close, conn) do
    {:stop, :normal, conn}
  end

  @impl true
  def handle_cast({:input, text}, conn) do
    {:noreply, process_input(conn, text)}
  end

  @impl true
  def handle_cast({:set_output_delimiters, delimiters}, conn) do
    new_options = Map.put(conn.connection_options, "output-delimiters", delimiters)
    {:noreply, %{conn | output_delimiters: delimiters, connection_options: new_options}}
  end

  @impl true
  def handle_cast({:set_connection_option, name, value}, conn) do
    new_options = Map.put(conn.connection_options, name, value)

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
    Enum.each(conn.waiting_tasks, &send(&1, {:input_received, ""}))
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
  def handle_call(:get_output_delimiters, _from, conn), do: {:reply, conn.output_delimiters, conn}

  @impl true
  def handle_call(:get_connection_options, _from, conn),
    do: {:reply, Map.keys(conn.connection_options), conn}

  @impl true
  def handle_call({:get_connection_option, name}, _from, conn),
    do: {:reply, Map.get(conn.connection_options, name), conn}

  @impl true
  def handle_info({:task_output, text}, conn) do
    {:noreply, queue_output(conn, text)}
  end

  @impl true
  def handle_info({ref, {:ok, result}}, %{active_task: %{ref: ref}} = conn) do
    # Cleanup task monitor
    Process.demonitor(ref, [:flush])
    conn = %{conn | active_task: nil}

    # Process result (check if login successful)
    case result do
      {:obj, player_id} when player_id >= 0 ->
        new_conn = finalize_login(conn, player_id)
        # Check if we have more input to process
        {:noreply, process_buffered_input(new_conn)}

      _ ->
        {:noreply, process_buffered_input(conn)}
    end
  end

  @impl true
  def handle_info({ref, {:error, reason}}, %{active_task: %{ref: ref}} = conn) do
    Process.demonitor(ref, [:flush])
    Logger.error("Login task failed: #{inspect(reason)}")
    {:noreply, %{conn | active_task: nil} |> process_buffered_input()}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{active_task: %{ref: ref}} = conn) do
    if reason != :normal do
      Logger.error("Login task crashed: #{inspect(reason)}")
    end

    {:noreply, %{conn | active_task: nil} |> process_buffered_input()}
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = conn) do
    conn = %{conn | last_activity: System.system_time(:second)}
    new_buffer = conn.input_buffer <> data
    {lines, remaining} = extract_lines(new_buffer)
    new_conn = Enum.reduce(lines, conn, &process_input(&2, &1))
    {:noreply, %{new_conn | input_buffer: remaining}}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %{socket: socket} = conn) do
    if conn.player_id && conn.player_id >= 0 do
      Logger.info("Player ##{conn.player_id} disconnected")
      MOOTask.kill_player_tasks(conn.player_id)
    else
      Logger.info("Connection closed (not logged in)")
    end

    {:stop, :normal, conn}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, conn) do
    Logger.error("Connection error: #{inspect(reason)}")
    {:stop, :normal, conn}
  end

  ## Private Helpers

  defp finalize_login(conn, player_id) do
    Logger.info("Connection #{conn.player_id} logged in as ##{player_id}")
    spawn_system_task("user_connected", [Value.obj(player_id)])
    %{conn | state: :logged_in, player_id: player_id}
  end

  defp run_login_task(conn, argstr, args) do
    case DB.find_verb(0, "do_login_command") do
      {:ok, 0, verb} ->
        runtime = Alchemoo.Runtime.new(DB.get_snapshot())

        env = %{
          :runtime => runtime,
          "player" => Value.obj(conn.player_id),
          "this" => Value.obj(0),
          "caller" => Value.obj(-1),
          "verb" => Value.str("do_login_command"),
          "args" => Value.list(Enum.map(args, &Value.str/1)),
          "argstr" => Value.str(argstr)
        }

        task_opts = [
          player: conn.player_id,
          this: 0,
          caller: -1,
          perms: 2,
          caller_perms: 2,
          args: Enum.map(args, &Value.str/1),
          handler_pid: self(),
          verb_name: "do_login_command"
        ]

        code = Enum.join(verb.code, "\n")

        # Start task asynchronously
        task =
          Task.async(fn ->
            MOOTask.run(code, env, task_opts)
          end)

        %{conn | active_task: task}

      _ ->
        Logger.error("Verb #0:do_login_command not found")
        conn
    end
  end

  defp process_input(conn, line) do
    line = String.trim(line)

    case conn.waiting_tasks do
      [task_pid | rest] ->
        send(task_pid, {:input_received, line})
        %{conn | waiting_tasks: rest}

      [] ->
        dispatch_input_by_state(conn, line)
    end
  end

  defp dispatch_input_by_state(conn, line) do
    if conn.active_task do
      # Busy, buffer the line (it stays in input_buffer essentially)
      # FUTURE: Better input queuing
      conn
    else
      do_dispatch_input_by_state(conn, line)
    end
  end

  defp do_dispatch_input_by_state(%{state: :connected} = conn, line) do
    words = String.split(line, " ", trim: true)
    run_login_task(conn, line, words)
  end

  defp do_dispatch_input_by_state(%{state: :logged_in} = conn, line) do
    process_moo_command(conn, line)
  end

  defp spawn_system_task(verb_name, args) do
    case DB.find_verb(0, verb_name) do
      {:ok, 0, verb} ->
        runtime = Alchemoo.Runtime.new(DB.get_snapshot())

        env = %{
          :runtime => runtime,
          "player" => hd(args),
          "this" => Value.obj(0),
          "caller" => Value.obj(-1),
          "verb" => Value.str(verb_name),
          "args" => Value.list(args)
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
        TaskSupervisor.spawn_task(code, env, task_opts)

      _ ->
        :ok
    end
  end

  defp process_moo_command(conn, line) do
    case line do
      "quit" ->
        send_text(conn, "Goodbye!\n")
        GenServer.cast(self(), :close)
        conn

      "@who" ->
        send_text(conn, "Connected players:\n  You\n")
        conn

      "@stats" ->
        stats = DB.stats()

        send_text(
          conn,
          "Database: #{stats.object_count} objects\nTasks: #{TaskSupervisor.count_tasks()}\n"
        )

        conn

      "" ->
        conn

      _ ->
        Executor.execute(line, conn.player_id, self())
        conn
    end
  end

  defp queue_output(conn, text) do
    if length(conn.output_queue) >= @max_output_queue do
      Logger.warning("Output queue full, dropping message")
      conn
    else
      flush_output(%{conn | output_queue: conn.output_queue ++ [text]})
    end
  end

  defp flush_output(conn) do
    case conn.output_queue do
      [] ->
        conn

      [text | rest] ->
        case send_text(conn, text) do
          :ok -> flush_output(%{conn | output_queue: rest})
          _ -> conn
        end
    end
  end

  defp send_text(conn, text), do: conn.transport.send(conn.socket, text)

  defp extract_lines(buffer) do
    lines = String.split(buffer, ["\n", "\r\n", "\r"], trim: true)

    if String.ends_with?(buffer, ["\n", "\r\n", "\r"]),
      do: {lines, ""},
      else:
        if(lines == [], do: {[], buffer}, else: {Enum.slice(lines, 0..-2//1), List.last(lines)})
  end

  defp process_buffered_input(conn) do
    # For now, just continue - the next handle_info({:tcp, ...}) will handle it
    # OR if we have lines in buffer, we should trigger process_input
    # FUTURE: Support explicit input queuing
    conn
  end
end
