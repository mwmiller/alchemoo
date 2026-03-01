defmodule Alchemoo.Connection.Handler do
  @moduledoc """
  Connection Handler manages a single player connection.
  Delegates un-logged-in input to #0:do_login_command.
  """
  use GenServer, restart: :temporary
  require Logger

  alias Alchemoo.Command.Executor
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Network.Readline
  alias Alchemoo.Runtime
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
    :readline_state,
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
    initial_message: nil,
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
    socket = Keyword.get(opts, :socket)
    transport = Keyword.get(opts, :transport, :ranch_tcp)
    player_id_opt = Keyword.get(opts, :player_id)

    peer_info = resolve_peer_info(socket, transport, Keyword.get(opts, :peer_info))
    conn_id = player_id_opt || -(1000 + :erlang.phash2(make_ref()))

    # If Telnet (ranch_tcp), negotiate options for Readline
    if transport == :ranch_tcp do
      # IAC WILL ECHO (255, 251, 1)
      # IAC WILL SGA (255, 251, 3)
      transport.send(socket, <<255, 251, 1, 255, 251, 3>>)
    end

    conn = %__MODULE__{
      socket: socket,
      transport: transport,
      connected_at: System.system_time(:second),
      last_activity: System.system_time(:second),
      peer_info: peer_info,
      player_id: conn_id,
      connection_options: initial_options(transport),
      initial_message: Keyword.get(opts, :initial_message)
    }

    Logger.info("New connection from #{peer_info} assigned ID #{conn_id}")

    {:ok, conn, {:continue, :initial_login}}
  end

  defp resolve_peer_info(socket, transport, initial_peer) do
    case transport && transport.peername(socket) do
      {:ok, {ip, port}} ->
        case :inet.ntoa(ip) do
          {:error, _} -> initial_peer || "unknown"
          address -> "#{address}:#{port}"
        end

      _ ->
        initial_peer || "unknown"
    end
  end

  defp initial_options(_transport) do
    # Telnet clients typically do local echo (client-echo 1)
    # SSH connections via our Readline module also handle their own echoing
    # so we set client-echo to 1 to prevent the Connection.Handler from
    # echoing the submitted line again.
    %{
      "binary" => 0,
      "hold-input" => 0,
      "client-echo" => 1,
      "flush-command" => ".flush",
      "output-delimiters" => ["", ""]
    }
  end

  defp system_tick_quota, do: Application.get_env(:alchemoo, :system_tick_quota, 1_000_003)

  @impl true
  def handle_continue(:initial_login, conn) do
    if conn.player_id && conn.player_id >= 0 do
      # Pre-authenticated (SSH)
      new_conn = finalize_login(conn, conn.player_id)
      {:noreply, new_conn}
    else
      # Trigger initial null do_login_command (no arguments)
      new_conn = run_login_task(conn, "", [])
      {:noreply, new_conn}
    end
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
  def handle_info({ref, {:ok, result}}, %{active_task: %{ref: ref} = active_task} = conn) do
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
        maybe_log_unrecognized_login_command(active_task, result)
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
    handle_input_data(conn, data)
  end

  @impl true
  def handle_info({:network_input, data}, conn) do
    handle_input_data(conn, data)
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %{socket: socket} = conn) do
    handle_network_closed(conn, :normal)
  end

  @impl true
  def handle_info({:network_closed, reason}, conn) do
    handle_network_closed(conn, reason)
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, conn) do
    Logger.error("Connection error: #{inspect(reason)}")
    {:stop, :normal, conn}
  end

  @impl true
  def handle_info({:network_error, reason}, conn) do
    Logger.error("Network error: #{inspect(reason)}")
    {:stop, :normal, conn}
  end

  @impl true
  def handle_info({:window_change, width, height}, conn) do
    # Handle SSH window change (SIGWINCH)
    # Could update player properties like linelen/num_lines here if desired
    Logger.info("Window changed for player ##{conn.player_id}: #{width}x#{height}")
    {:noreply, conn}
  end

  @impl true
  def terminate(reason, conn) do
    if trace_connections?(),
      do: Logger.debug("Connection handler #{conn.player_id} terminating: #{inspect(reason)}")

    if conn.player_id && conn.player_id >= 0 do
      try do
        MOOTask.kill_player_tasks(conn.player_id)
      catch
        kind, reason ->
          Logger.error("Error killing player tasks during terminate: #{inspect({kind, reason})}")
      end
    end

    if conn.transport && conn.socket do
      conn.transport.close(conn.socket)
    end

    :ok
  end

  defp handle_input_data(conn, data) do
    conn = %{conn | last_activity: System.system_time(:second)}

    # Process Telnet commands first if any
    {clean_data, conn} = process_telnet_commands(data, conn)

    if clean_data == "" do
      {:noreply, conn}
    else
      # Use Readline for line editing if available
      # (SSH always has it, Telnet has it if we negotiated WILL ECHO/SGA)
      readline_state = conn.readline_state || Readline.new(conn.socket, conn.transport)

      case Readline.handle_input(clean_data, readline_state) do
        {:ok, next_state} ->
          {:noreply, %{conn | readline_state: next_state}}

        {:line, line, next_state} ->
          new_conn = process_input(%{conn | readline_state: next_state}, line)
          {:noreply, new_conn}
      end
    end
  end

  defp handle_network_closed(conn, _reason) do
    if conn.player_id && conn.player_id >= 0 do
      Logger.info("Player ##{conn.player_id} disconnected")
      MOOTask.kill_player_tasks(conn.player_id)
    else
      Logger.info("Connection closed (not logged in)")
    end

    {:stop, :normal, conn}
  end

  ## Private Helpers

  defp finalize_login(conn, player_id) do
    # Disconnect any existing connections for this player
    redirected? = boot_existing_connection(player_id)

    # Initialize connection properties in DB before core verbs see them
    now = System.system_time(:second)

    # Standard MOO previous_connection format is {time, host_string}
    last_time =
      case DB.get_property(player_id, "last_connect_time") do
        {:ok, {:num, t}} -> Value.num(t)
        _ -> Value.num(0)
      end

    # Update previous_connection with the OLD data
    DB.set_property(
      player_id,
      "previous_connection",
      Value.list([last_time, Value.str(conn.peer_info)])
    )

    # Update last_connect_time with the NEW data
    DB.set_property(player_id, "last_connect_time", Value.num(now))

    Logger.info("Connection #{conn.player_id} logged in as ##{player_id}")
    spawn_system_task("user_connected", [Value.obj(player_id)])

    conn =
      if redirected? do
        queue_output(conn, "\n*** Redirecting old connection to this port ***\n")
      else
        conn
      end

    conn =
      if conn.initial_message do
        queue_output(conn, conn.initial_message)
      else
        conn
      end

    %{conn | state: :logged_in, player_id: player_id}
  end

  defp boot_existing_connection(player_id) do
    # Get all connection handlers
    pids =
      Alchemoo.Connection.Supervisor.list_connections()
      |> Enum.filter(&(&1 != self()))

    Enum.reduce(pids, false, fn pid, acc ->
      case info(pid) do
        %{player_id: ^player_id, state: :logged_in} ->
          Logger.info("Booting existing connection for ##{player_id} (PID #{inspect(pid)})")
          send_output(pid, "\n*** Disconnected: another connection has been established. ***\n")
          close(pid)
          true

        _ ->
          acc
      end
    end)
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
          verb_name: "do_login_command",
          tick_quota: system_tick_quota()
        ]

        code = Enum.join(verb.code, "\n")

        # Start task asynchronously
        task =
          Task.async(fn ->
            MOOTask.run(code, env, task_opts)
          end)

        %{conn | active_task: %{ref: task.ref, task: task, argstr: argstr, args: args}}

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
          verb_name: verb_name,
          tick_quota: system_tick_quota()
        ]

        code = Enum.join(verb.code, "\n")
        TaskSupervisor.spawn_task(code, env, task_opts)

      _ ->
        :ok
    end
  end

  defp process_moo_command(conn, line) do
    if line == "" do
      conn
    else
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

  defp send_text(%{transport: nil}, _text) do
    # For testing or internal connections
    :ok
  end

  defp send_text(conn, text) do
    # Standard terminal behavior (Telnet/SSH) requires \r\n for newlines
    # to return the cursor to the start of the line.
    # We normalize all combinations (\r\n, \n, \r) to \r\n.
    normalized_text =
      text
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")
      |> String.replace("\n", "\r\n")

    if Application.get_env(:alchemoo, :trace_output, false) do
      Logger.debug("Network Send (raw): #{inspect(normalized_text)}")
    end

    conn.transport.send(conn.socket, normalized_text)
  rescue
    _ ->
      Logger.error("Failed to send text via transport #{inspect(conn.transport)}")
      {:error, :transport_failed}
  end

  defp process_buffered_input(conn) do
    # For now, just continue - the next handle_info({:tcp, ...}) will handle it
    # OR if we have lines in buffer, we should trigger process_input
    # FUTURE: Support explicit input queuing
    conn
  end

  defp maybe_log_unrecognized_login_command(%{argstr: ""}, _result), do: :ok

  defp maybe_log_unrecognized_login_command(%{argstr: argstr, args: args}, result) do
    if Application.get_env(:alchemoo, :log_login_resolution, true) do
      parse_resolution = diagnose_login_parse_command(args, argstr)

      if login_parse_fell_back?(args, parse_resolution) do
        Logger.warning(
          "Unrecognized login command: argstr=#{inspect(argstr)} args=#{inspect(args)} result=#{inspect(result)} parse=#{inspect(parse_resolution)}"
        )
      end
    end
  end

  defp diagnose_login_parse_command(args, argstr) do
    runtime = Runtime.new(DB.get_snapshot())
    arg_vals = Enum.map(args, &Value.str/1)

    env = %{
      :runtime => runtime,
      "player" => Value.obj(-1),
      "this" => Value.obj(0),
      "caller" => Value.obj(-1),
      "verb" => Value.str("do_login_command"),
      "args" => Value.list(arg_vals),
      "argstr" => Value.str(argstr)
    }

    prev_ctx = Process.get(:task_context)

    Process.put(:task_context, %{
      this: 0,
      player: -1,
      caller: -1,
      perms: 2,
      caller_perms: 2,
      verb_definer: 0,
      verb_name: "do_login_command",
      stack: []
    })

    result =
      case Runtime.call_verb(runtime, Value.obj(10), "parse_command", arg_vals, env) do
        {:ok, value, _new_runtime} -> value
        {:error, err} -> err
      end

    Process.put(:task_context, prev_ctx)
    result
  end

  defp login_parse_fell_back?(input_args, {:list, [{:str, parsed_verb} | _]}) do
    input_verb =
      case input_args do
        [first | _] -> first
        _ -> ""
      end

    parsed_verb == "?" and input_verb != "?"
  end

  defp login_parse_fell_back?(_input_args, _parse), do: false

  defp process_telnet_commands(<<>>, conn), do: {"", conn}

  defp process_telnet_commands(<<255, cmd, opt, rest::binary>>, conn)
       when cmd in [251, 252, 253, 254] do
    # Handle DO/DONT/WILL/WONT
    new_conn = handle_telnet_option(conn, cmd, opt)
    process_telnet_commands(rest, new_conn)
  end

  defp process_telnet_commands(<<255, _cmd, rest::binary>>, conn) do
    # Handle other IAC (like IAC IAC for literal 255)
    process_telnet_commands(rest, conn)
  end

  defp process_telnet_commands(<<byte, rest::binary>>, conn) do
    {others, next_conn} = process_telnet_commands(rest, conn)
    {<<byte>> <> others, next_conn}
  end

  defp handle_telnet_option(conn, cmd, opt) do
    case {cmd, opt} do
      {253, 1} ->
        # Client says DO ECHO (meaning I should echo)
        # Confirmation for WILL ECHO
        put_in(conn.connection_options["client-echo"], 0)

      {253, 3} ->
        # Confirmation for WILL SGA
        conn

      _ ->
        conn
    end
  end

  defp trace_connections?, do: Application.get_env(:alchemoo, :trace_connections, false)
end
