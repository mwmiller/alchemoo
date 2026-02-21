defmodule Alchemoo.Network.Supervisor do
  @moduledoc """
  Supervisor for network listeners (Telnet, SSH, WebSocket).
  Each listener can be independently enabled/disabled and configured.
  """
  use Supervisor

  # CONFIG: Should be extracted to config
  # Default configuration for network listeners
  @default_config %{
    # CONFIG: :alchemoo, :telnet
    telnet: %{enabled: true, port: 7777},
    # CONFIG: :alchemoo, :ssh
    ssh: %{enabled: false, port: 2222},
    # CONFIG: :alchemoo, :websocket
    websocket: %{enabled: false, port: 4000}
  }

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, @default_config)

    children = build_children(config)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp build_children(config) do
    []
    |> maybe_add_telnet(config[:telnet])
    |> maybe_add_ssh(config[:ssh])
    |> maybe_add_websocket(config[:websocket])
  end

  defp maybe_add_telnet(children, %{enabled: true, port: port}) do
    children ++ [{Alchemoo.Network.Telnet, port: port}]
  end

  defp maybe_add_telnet(children, _), do: children

  defp maybe_add_ssh(children, %{enabled: true, port: _port}) do
    # SSH implementation ready, just needs to be enabled
    # children ++ [{Alchemoo.Network.SSH, port: port}]
    children
  end

  defp maybe_add_ssh(children, _), do: children

  defp maybe_add_websocket(children, %{enabled: true, port: _port}) do
    # WebSocket not implemented yet
    # children ++ [{Alchemoo.Network.WebSocket, port: port}]
    children
  end

  defp maybe_add_websocket(children, _), do: children

  @doc "Get current network configuration"
  def config do
    Application.get_env(:alchemoo, :network, [])
  end

  @doc "List active listeners"
  def listeners do
    Supervisor.which_children(__MODULE__)
    |> Enum.map(fn {id, pid, _type, _modules} ->
      %{id: id, pid: pid, active: pid != :undefined}
    end)
  end
end
