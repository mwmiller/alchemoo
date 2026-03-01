defmodule Alchemoo.Network.SSH.Transport do
  @moduledoc """
  Implements the transport-adapter interface for Connection.Handler
  to use when communicating over SSH.
  """
  require Logger

  # SSH transport: socket is a tuple {connection_handler, channel_id}
  def send({connection_handler, channel_id}, text) do
    :ssh_connection.send(connection_handler, channel_id, text)
  end

  def close({connection_handler, channel_id}) do
    :ssh_connection.close(connection_handler, channel_id)
  end

  def peername({connection_handler, _channel_id}) do
    # Get the underlying socket and use :inet.peername for reliability
    case :ssh.connection_info(connection_handler, [:socket]) do
      [socket: socket] -> :inet.peername(socket)
      _ -> {:error, :unknown}
    end
  end

  # Helper to set opts? SSH doesn't use the same :active opts.
  def setopts(_socket, _opts), do: :ok
  def controlling_process(_socket, _pid), do: :ok
end
