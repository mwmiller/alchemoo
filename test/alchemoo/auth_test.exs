defmodule Alchemoo.AuthTest do
  use ExUnit.Case, async: false
  alias Alchemoo.Auth
  alias Alchemoo.Database.Server, as: DB

  setup do
    # Create a test player with unique name to avoid cross-test interference
    name = "TestPlayer_#{:erlang.unique_integer([:positive])}"
    password = "password123"

    {:ok, player_id} = Auth.create_player(name, password)
    {:ok, player_id: player_id, name: name, password: password}
  end

  test "login successful with correct password", %{
    name: name,
    password: password,
    player_id: player_id
  } do
    assert {:ok, ^player_id} = Auth.login(name, password)
  end

  test "login fails with incorrect password", %{name: name} do
    assert {:error, :invalid_password} = Auth.login(name, "wrong")
  end

  test "login fails with unknown player" do
    assert {:error, :not_found} = Auth.login("NonExistentPlayerXYZ", "foo")
  end

  test "login successful with empty password if not set" do
    # Create a player and manually clear their password (set to 0)
    name = "NoPasswordPlayer_#{:erlang.unique_integer([:positive])}"
    {:ok, id} = Auth.create_player(name, "initial")
    DB.set_property(id, "password", Alchemoo.Value.num(0))

    assert {:ok, ^id} = Auth.login(name, "")
  end
end
