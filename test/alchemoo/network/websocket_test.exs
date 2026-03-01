defmodule Alchemoo.Network.WebSocketTest do
  use ExUnit.Case, async: false
  require Logger

  setup_all do
    # Ensure the application is started
    Application.ensure_all_started(:alchemoo)
    :ok
  end

  defp get_good_port do
    seed =
      case ExUnit.configuration()[:seed] do
        nil -> :erlang.phash2(make_ref(), 10_000)
        0 -> :erlang.phash2(make_ref(), 10_000)
        val -> val
      end

    30_011 + rem(seed, 9973)
  end

  setup do
    # Use the random port selection pattern from config/test.exs
    port = get_good_port()
    
    # Start a local WebSocket listener on this port
    # We use a unique ID to avoid conflict with the one from the app
    # if it's already running.
    child_spec = Supervisor.child_spec({Alchemoo.Network.WebSocket, port: port}, id: :test_websocket)
    
    _pid = start_supervised!(child_spec)
    
    # Wait for it to start
    :timer.sleep(100)

    {:ok, port: port}
  end

  defmodule TestClient do
    use WebSockex

    def start_link(url, receiver) do
      WebSockex.start_link(url, __MODULE__, %{receiver: receiver})
    end

    def handle_frame({:text, msg}, state) do
      send(state.receiver, {:ws_msg, msg})
      {:ok, state}
    end

    def handle_cast({:send, msg}, state) do
      {:reply, {:text, msg}, state}
    end
  end

  test "can connect and receive initial login message", %{port: port} do
    url = "ws://localhost:#{port}/"
    {:ok, client} = TestClient.start_link(url, self())

    # Wait for initial login output from #0:do_login_command
    wait_for_content(5000)
    
    # Clean up
    Process.exit(client, :normal)
  end

  test "can send commands and receive output", %{port: port} do
    url = "ws://localhost:#{port}/"
    {:ok, client} = TestClient.start_link(url, self())

    # Skip banner
    wait_for_content(5000)

    # Try to login or just send a command
    WebSockex.cast(client, {:send, "help"})

    msg = wait_for_content(5000)
    assert String.contains?(msg, "help") or String.contains?(msg, "I don't understand") or String.contains?(msg, "connect") or String.contains?(msg, "Usage")

    # Clean up
    Process.exit(client, :normal)
  end

  defp wait_for_content(timeout) do
    receive do
      {:ws_msg, msg} ->
        if String.trim(msg) == "" do
          wait_for_content(timeout)
        else
          msg
        end
    after
      timeout -> flunk("Timed out waiting for non-empty WebSocket message")
    end
  end
end
