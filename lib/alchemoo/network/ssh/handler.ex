defmodule Alchemoo.Network.SSH.Handler do
  @moduledoc """
  Bridges SSH channel events to Alchemoo.Connection.Handler.
  Implements the :ssh_server_channel behavior.
  """
  require Logger
  alias Alchemoo.Auth.SSH, as: AuthSSH
  alias Alchemoo.Connection.Supervisor, as: ConnSup
  alias Alchemoo.Network.SSH.Transport, as: SSHTransport

  @behaviour :ssh_server_channel

  @impl :ssh_server_channel
  def init(_args) do
    {:ok,
     %{
       channel_id: nil,
       connection_handler: nil,
       handler_pid: nil,
       user: nil
     }}
  end

  @impl :ssh_server_channel
  def handle_ssh_msg({:ssh_cm, _cm, {:data, _channel_id, _type, data}}, state) do
    if trace_ssh?(), do: Logger.debug("SSH Channel received data: #{inspect(data)}")

    if state.handler_pid do
      send(state.handler_pid, {:network_input, data})
    end

    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, cm, {:shell, channel_id, want_reply}}, state) do
    if trace_ssh?(), do: Logger.debug("SSH Channel shell request (want_reply: #{want_reply})")
    # Shell requested - start the Connection.Handler
    # Note: promotion_result will be handled later since Process dictionary doesn't cross
    promotion_result = nil

    case start_connection_handler(state, cm, channel_id, promotion_result) do
      {:ok, pid} ->
        if trace_ssh?(), do: Logger.debug("SSH Connection Handler started: #{inspect(pid)}")
        if want_reply, do: :ssh_connection.reply_request(cm, true, :success, channel_id)
        {:ok, %{state | handler_pid: pid, connection_handler: cm, channel_id: channel_id}}

      {:error, reason} ->
        Logger.error("SSH Failed to start connection handler: #{inspect(reason)}")
        if want_reply, do: :ssh_connection.reply_request(cm, true, :failure, channel_id)
        {:ok, state}
    end
  end

  def handle_ssh_msg({:ssh_cm, cm, {:pty, channel_id, want_reply, _terminal_info}}, state) do
    if trace_ssh?(), do: Logger.debug("SSH Channel PTY request (want_reply: #{want_reply})")
    # Just acknowledge PTY request
    if want_reply, do: :ssh_connection.reply_request(cm, true, :success, channel_id)
    {:ok, %{state | connection_handler: cm, channel_id: channel_id}}
  end

  def handle_ssh_msg({:ssh_cm, cm, {:window_change, channel_id, width, height}}, state) do
    if trace_ssh?(), do: Logger.debug("SSH Channel window change: #{width}x#{height}")

    if state.handler_pid do
      send(state.handler_pid, {:window_change, width, height})
    end

    {:ok, %{state | connection_handler: cm, channel_id: channel_id}}
  end

  def handle_ssh_msg({:ssh_cm, _cm, {:eof, _channel_id}}, state) do
    if trace_ssh?(), do: Logger.debug("SSH Channel received EOF")
    if state.handler_pid, do: send(state.handler_pid, :network_closed)
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _cm, {:closed, _channel_id}}, state) do
    if trace_ssh?(), do: Logger.debug("SSH Channel closed")
    if state.handler_pid, do: send(state.handler_pid, :network_closed)
    {:stop, :normal, state}
  end

  def handle_ssh_msg({:ssh_cm, cm, {:env, channel_id, want_reply, var, val}}, state) do
    if trace_ssh?(), do: Logger.debug("SSH Channel env request: #{inspect(var)}=#{inspect(val)}")
    if want_reply, do: :ssh_connection.reply_request(cm, true, :success, channel_id)
    {:ok, state}
  end

  @impl :ssh_server_channel
  def handle_msg({:ssh_channel_up, channel_id, cm}, state) do
    if trace_ssh?(), do: Logger.debug("SSH Channel UP: #{channel_id}")

    # Get user info from connection
    user =
      case :ssh.connection_info(cm, [:user]) do
        [user: u] -> to_string(user_to_binary(u))
        _ -> "unknown"
      end

    if trace_ssh?(), do: Logger.debug("SSH User resolved: #{user}")
    {:ok, %{state | channel_id: channel_id, connection_handler: cm, user: user}}
  end

  def handle_msg(msg, state) do
    if trace_ssh?(),
      do: Logger.debug("SSH Channel received unknown Erlang message: #{inspect(msg)}")

    {:ok, state}
  end

  @impl :ssh_server_channel
  def terminate(reason, _state) do
    if trace_ssh?(), do: Logger.debug("SSH Channel terminating: #{inspect(reason)}")
    :ok
  end

  ## Private Helpers

  defp trace_ssh?, do: Application.get_env(:alchemoo, :trace_ssh, false)

  defp start_connection_handler(state, cm, channel_id, _promotion_result) do
    player_id = resolve_player_id(state.user)
    socket = {cm, channel_id}

    # Re-check promotion (idempotent) to get the result in this process
    promotion_result = AuthSSH.promote_cached_key(state.user)
    initial_message = AuthSSH.get_promotion_message(promotion_result)

    ConnSup.start_connection(socket, SSHTransport,
      player_id: player_id,
      initial_message: initial_message
    )
  end

  defp resolve_player_id(username) do
    case AuthSSH.resolve_player_id(username) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  defp user_to_binary(u) when is_list(u), do: List.to_string(u)
  defp user_to_binary(u) when is_binary(u), do: u
  defp user_to_binary(u), do: inspect(u)
end
