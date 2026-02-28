defmodule Alchemoo.Network.SSH do
  @moduledoc """
  Manages the SSH daemon and listener.
  Handles host key generation and daemon lifecycle.
  """
  use GenServer
  require Logger

  alias Alchemoo.Auth.SSH, as: AuthSSH
  alias Alchemoo.Network.SSH.Handler, as: SSHHandler

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Ensure SSH is started (the application)
    :ok = :ssh.start()

    # Initialize SSH auth (DETS storage)
    AuthSSH.init()

    # Ensure host keys exist
    host_key_dir = ensure_host_keys()

    # Start the daemon
    port = Keyword.get(opts, :port, 2222)

    daemon_opts = [
      ssh_cli: {SSHHandler, []},
      key_cb: {Alchemoo.Network.SSH.KeyHandler, []},
      system_dir: to_charlist(host_key_dir),
      user_dir: to_charlist(host_key_dir),
      pwdfun: &verify_password/2,
      preferred_algorithms: :ssh.default_algorithms()
    ]

    case :ssh.daemon(port, daemon_opts) do
      {:ok, ref} ->
        Logger.info("SSH server listening on port #{port}")
        {:ok, %{ref: ref, port: port}}

      {:error, reason} ->
        Logger.error("Failed to start SSH server: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp verify_password(user, password) do
    username = to_string(user)
    pass_str = to_string(password)

    Logger.debug(
      "SSH login attempt for '#{username}' with password length #{String.length(pass_str)}"
    )

    # Bridging to Alchemoo.Auth.SSH
    case AuthSSH.verify_password(username, pass_str) do
      {:ok, _player_id, promotion_result} ->
        Logger.info("SSH login successful for '#{username}'")
        Process.put(:ssh_promotion_result, promotion_result)
        true

      {:error, reason} ->
        Logger.warning("SSH login failed for '#{username}': #{inspect(reason)}")
        false

      _ ->
        false
    end
  end

  defp ensure_host_keys do
    base_dir = Application.get_env(:alchemoo, :base_dir)
    ssh_dir = Path.join(base_dir, "ssh")
    host_key_dir = Path.join(ssh_dir, "host_keys")
    File.mkdir_p!(host_key_dir)

    # If no keys exist, generate a default one
    case File.ls!(host_key_dir) do
      [] ->
        Logger.info("Generating SSH host keys in #{host_key_dir}...")
        generate_host_key(host_key_dir)

      _ ->
        :ok
    end

    host_key_dir
  end

  defp generate_host_key(dir) do
    # Generate an RSA host key using ssh-keygen if available,
    # or fallback to Erlang if we want to be pure.
    # For now, let's use ssh-keygen for simplicity if available.
    path = Path.join(dir, "ssh_host_rsa_key")
    System.cmd("ssh-keygen", ["-t", "rsa", "-f", path, "-N", "", "-q"])
  rescue
    _ ->
      Logger.warning("ssh-keygen not found. SSH daemon may fail if no host keys are provided.")
  end
end
