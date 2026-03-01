defmodule Alchemoo.Auth.SSH do
  @moduledoc """
  Handles SSH authentication logic:
  - Verifying MOO passwords for SSH login.
  - Managing external public key storage (DETS).
  - Verifying public keys against the external store.
  """
  require Logger
  alias Alchemoo.Database.Flags
  alias Alchemoo.Database.Resolver
  alias Alchemoo.Database.Server, as: DB

  @dets_name :alchemoo_ssh_keys
  @cache_name :alchemoo_ssh_cache

  @doc "Initialize the SSH key storage"
  def init do
    base_dir = Application.get_env(:alchemoo, :base_dir)
    ssh_dir = Path.join(base_dir, "ssh")
    File.mkdir_p!(ssh_dir)

    path = Path.join(ssh_dir, "authorized_keys.dets")

    # Create volatile cache for attempted keys (user -> key)
    :ets.new(@cache_name, [:named_table, :public, :set, {:read_concurrency, true}])

    case :dets.open_file(@dets_name, file: to_charlist(path), type: :set) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to open SSH key storage: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Verify a MOO user password for SSH"
  def verify_password(username, password) do
    # Bridging to the existing Alchemoo.Auth.login logic for unified password check
    case Alchemoo.Auth.login(username, password) do
      {:ok, player_id} ->
        # Successfully logged in via password - promote any cached key
        # and return the result so the handler can notify
        promotion_result = promote_cached_key(username)
        {:ok, player_id, promotion_result}

      error ->
        error
    end
  end

  @doc "Promote and return a notification message if successful"
  def get_promotion_message({:ok, :authorized_new}) do
    """
    *** NOTICE: A new SSH public key has been automatically authorized for your account.
    *** Future logins from this SSH client will no longer require a password.
    """
  end

  def get_promotion_message(_), do: nil

  @doc "Check if a public key is authorized for a user"
  def key_authorized?(username, public_key) do
    # Record the attempt - we might promote this if password succeeds
    cache_attempted_key(username, public_key)

    case resolve_player_id(username) do
      {:ok, player_id} when player_id != nil ->
        check_keys_in_dets(player_id, public_key)

      _ ->
        false
    end
  end

  @doc "Cache an attempted public key for a user (volatile)"
  def cache_attempted_key(username, public_key) do
    # Cache for a short time (e.g., 5 minutes) to allow password fallback
    # user -> {timestamp, public_key}
    :ets.insert(@cache_name, {username, {System.system_time(:second), public_key}})
  end

  @doc "Promote the last attempted key for a user to their authorized keys"
  def promote_cached_key(username) do
    case :ets.lookup(@cache_name, username) do
      [{^username, {timestamp, public_key}}] ->
        maybe_promote_key(username, timestamp, public_key)

      [] ->
        {:error, :no_cached_key}
    end
  end

  defp maybe_promote_key(username, timestamp, public_key) do
    # Check if the attempt was recent (within 5 minutes)
    if System.system_time(:second) - timestamp < 300 do
      do_promote_key(username, public_key)
    else
      {:error, :expired}
    end
  end

  defp do_promote_key(username, public_key) do
    case resolve_player_id(username) do
      {:ok, player_id} when player_id != nil ->
        keys = get_keys(player_id)

        if public_key in keys do
          {:ok, :already_authorized}
        else
          Logger.info("Automatically authorized new SSH key for player ##{player_id}")
          :dets.insert(@dets_name, {player_id, [public_key | keys]})
          :dets.sync(@dets_name)
          {:ok, :authorized_new}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp check_keys_in_dets(player_id, public_key) do
    case :dets.lookup(@dets_name, player_id) do
      [{^player_id, keys}] when is_list(keys) ->
        # public_key is an Erlang record/term from :ssh
        Enum.any?(keys, fn k -> k == public_key end)

      _ ->
        false
    end
  end

  @doc "Add an authorized key for a player"
  def add_key(player_id, key_string) when is_binary(key_string) do
    case decode_ssh_key(key_string) do
      {:ok, public_key} ->
        keys = get_keys(player_id)

        if public_key in keys do
          :ok
        else
          :dets.insert(@dets_name, {player_id, [public_key | keys]})
          :dets.sync(@dets_name)
        end

      error ->
        error
    end
  end

  @doc "Remove an authorized key for a player"
  def remove_key(player_id, key_index) when is_integer(key_index) do
    keys = get_keys(player_id)

    if key_index >= 1 and key_index <= length(keys) do
      new_keys = List.delete_at(keys, key_index - 1)
      :dets.insert(@dets_name, {player_id, new_keys})
      :dets.sync(@dets_name)
      :ok
    else
      {:error, :E_RANGE}
    end
  end

  @doc "List authorized keys for a player (as strings with fingerart)"
  def list_keys(player_id) do
    get_keys(player_id)
    |> Enum.map(fn key ->
      # Convert key term to string and generate fingerart
      case encode_ssh_key(key) do
        {:ok, key_str, art, fingerprint} -> [key_str, art, fingerprint]
        _ -> ["unknown", "", ""]
      end
    end)
  end

  ## Helpers

  @doc "Resolve a username to a player ID"
  def resolve_player_id(name) do
    if name == "guest" do
      {:ok, nil}
    else
      # 1. Find all players
      all_players =
        DB.get_snapshot().objects
        |> Map.values()
        |> Enum.filter(fn obj ->
          Flags.set?(obj.flags, Flags.user())
        end)
        |> Enum.map(fn obj -> obj.id end)

      # 2. Match name against players
      Resolver.match(name, all_players)
    end
  end

  defp get_keys(player_id) do
    case :dets.lookup(@dets_name, player_id) do
      [{^player_id, keys}] -> keys
      _ -> []
    end
  end

  defp decode_ssh_key(key_string) do
    # Handle common formats (OpenSSH)
    [_type | rest] = String.split(key_string, " ", trim: true)

    case rest do
      [base64_data | _] ->
        data = Base.decode64!(base64_data)
        # Use :ssh_file.decode/2 for binary data
        # It returns [{Key, Attributes}]
        case :ssh_file.decode(data, :public_key) do
          {:ok, [{key, _attrs} | _]} -> {:ok, key}
          {:ok, [key | _]} -> {:ok, key}
          _ -> {:error, :invalid_key_format}
        end

      _ ->
        {:error, :invalid_key_format}
    end
  rescue
    _ -> {:error, :invalid_key_format}
  end

  defp encode_ssh_key(public_key) do
    # public_key is an Erlang record (e.g., #'RSAPublicKey'{})
    # For the string part, we want a label (e.g., "ssh-rsa")
    type = get_key_type(public_key)
    {fingerprint, hash_bin} = get_fingerprint(public_key)

    # Fingerart works with the 16-byte MD5 hash for standard SSH randomart
    art = Fingerart.generate(hash_bin, title: type)

    {:ok, type, art, fingerprint}
  rescue
    _ -> {:error, :encode_failed}
  end

  defp get_fingerprint(public_key) do
    # Standard SSH fingerprint is MD5 of the blob (traditionally)
    # or SHA256. For legacy compatibility and 'classic' look, MD5 hex is common.
    # Erlang public_key can give us the DER blob
    blob = :erlang.term_to_binary(public_key)
    hash_bin = :crypto.hash(:md5, blob)
    hash_hex = Base.encode16(hash_bin, case: :lower)

    # Format as pairs: aa:bb:cc...
    fingerprint =
      hash_hex
      |> String.graphemes()
      |> Enum.chunk_every(2)
      |> Enum.map_join(":", &Enum.join/1)

    {fingerprint, hash_bin}
  end

  defp get_key_type(key) when is_tuple(key) do
    case elem(key, 0) do
      :RSAPublicKey -> "ssh-rsa"
      :DSAPublicKey -> "ssh-dss"
      :ecdsa_public_key -> "ecdsa-sha2-nistp256"
      :eddsa_public_key -> "ssh-ed25519"
      _ -> "unknown-key-type"
    end
  end

  defp get_key_type(_), do: "unknown"
end
