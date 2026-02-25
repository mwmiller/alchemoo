defmodule Alchemoo.Auth do
  @moduledoc """
  Authentication logic for Alchemoo.
  """
  require Logger

  alias Alchemoo.Builtins
  alias Alchemoo.Database.Flags
  alias Alchemoo.Database.Resolver
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Value

  @doc """
  Attempt to log in a player with name and password.

  Returns:
    {:ok, player_id} - Login successful
    {:error, :not_found} - Player name not found
    {:error, :invalid_password} - Password does not match
  """
  def login(name, password) do
    # 1. Find all players
    all_players =
      DB.get_snapshot().objects
      |> Map.values()
      |> Enum.filter(fn obj ->
        Flags.set?(obj.flags, Flags.user())
      end)
      |> Enum.map(fn obj -> obj.id end)

    # 2. Match name against players
    case Resolver.match(name, all_players) do
      {:ok, player_id} ->
        # 3. Verify password using check_password built-in logic
        case Builtins.call(:check_password, [Value.obj(player_id), Value.str(password)]) do
          {:num, 1} ->
            {:ok, player_id}

          _ ->
            {:error, :invalid_password}
        end

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Create a new player.
  """
  def create_player(name, password) do
    # 1. Find player prototype ($player)
    parent_id = Resolver.object(:player)

    # 2. Create the object
    case DB.create_object(parent_id) do
      {:ok, player_id} ->
        # 3. Set name and password
        # name is a built-in property, so set_property works
        DB.set_property(player_id, "name", Value.str(name))

        hash = Builtins.call(:crypt, [Value.str(password)])
        # password is not built-in, so must be added
        DB.add_property(player_id, "password", hash, player_id, "")

        # 4. Set player flag
        DB.set_player_flag(player_id, true)

        Logger.info("Created new player '#{name}' (##{player_id})")
        {:ok, player_id}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
