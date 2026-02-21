defmodule Alchemoo.Network.SSH do
  @moduledoc """
  SSH server for Alchemoo. Provides secure shell access to the MOO.

  ## Features (Planned)

  - Public key authentication
  - Password authentication (optional)
  - Fingerprint visualization using fingerart (drunken bishop)
  - SFTP support (optional)

  ## Configuration

  ```elixir
  config :alchemoo,
    network: %{
      ssh: %{
        enabled: true,
        port: 2222,
        host_key_path: "/etc/alchemoo/ssh_host_key",
        authorized_keys_path: "/etc/alchemoo/authorized_keys",
        show_fingerprint: true  # Uses fingerart for drunken bishop display
      }
    }
  ```

  ## Dependencies

  Requires:
  - `:ssh` (built-in Erlang)
  - `:fingerart` (optional, for fingerprint visualization)

  ## Implementation Notes

  When implementing SSH support:

  1. Use Erlang's `:ssh` application
  2. Generate host keys on first start
  3. Display fingerprint using fingerart on connection
  4. Hand off authenticated connections to Connection.Handler
  5. Support both password and public key auth

  ## Example Fingerprint Display

  ```
  The authenticity of host '[localhost]:2222' can't be established.
  ED25519 key fingerprint is SHA256:abc123...
  +--[ED25519 256]--+
  |       .o+*      |
  |      . .=.o     |
  |       o.o+      |
  |      . =+.      |
  |       oS+.      |
  |      . *+.      |
  |       =.*.      |
  |      . B.o      |
  |       o.E       |
  +----[SHA256]-----+
  ```

  ## TODO

  - [ ] Implement SSH server using :ssh
  - [ ] Generate/load host keys
  - [ ] Integrate fingerart for fingerprint display
  - [ ] Add to Network.Supervisor
  - [ ] Add authentication callbacks
  - [ ] Add connection handler integration
  """

  # Placeholder for future implementation

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(_opts) do
    # TODO: Implement SSH server
    :ignore
  end
end
