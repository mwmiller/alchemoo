defmodule Alchemoo.Network.Telnet.Transport do
  @moduledoc """
  Wraps :ranch_tcp to provide a consistent transport interface.
  """
  
  def send(socket, data), do: :ranch_tcp.send(socket, data)
  def close(socket), do: :ranch_tcp.close(socket)
  def peername(socket), do: :ranch_tcp.peername(socket)
  def setopts(socket, opts), do: :ranch_tcp.setopts(socket, opts)
  def controlling_process(socket, pid), do: :ranch_tcp.controlling_process(socket, pid)

  def use_readline?, do: true
  def default_echo?, do: true

  @doc """
  Processes Telnet-specific commands (IAC sequences) and strips them from the data stream.
  """
  def preprocess(data, conn) do
    process_telnet_commands(data, conn)
  end

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
        new_options = Map.put(conn.connection_options, "client-echo", 0)
        %{conn | connection_options: new_options}

      {253, 3} ->
        # Confirmation for WILL SGA
        conn

      _ ->
        conn
    end
  end
end
