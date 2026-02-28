defmodule Alchemoo.Network.SSH.KeyHandler do
  @moduledoc """
  Implements the SSH 'key_cb' callback for user authentication.
  Uses Alchemoo.Auth.SSH (DETS) for checking keys.
  """
  require Logger
  alias Alchemoo.Auth.SSH, as: AuthSSH

  # behavior: ssh_server_key_api

  @doc "Validate the server's own host key"
  def host_key(algorithm, options) do
    # Delegate host key management to ssh_file
    # This reads from /path/to/ssh/host_key
    :ssh_file.host_key(algorithm, options)
  end

  @doc "Validate a client's public key for authentication"
  # credo:disable-for-next-line
  def is_auth_key(public_key, user_bin, _options) do
    username = to_string(user_bin)

    # Check external key storage (DETS)
    AuthSSH.key_authorized?(username, public_key)
  end
end
