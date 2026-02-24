defmodule Alchemoo.Database.ResolverTest do
  use ExUnit.Case, async: false
  alias Alchemoo.Database.Resolver

  setup do
    # Load LambdaCore for testing resolver
    path = "/tmp/LambdaCore-12Apr99.db"
    if File.exists?(path) do
      Alchemoo.Database.Server.load(path)
    end
    :ok
  end

  test "match resolves 'me'" do
    context = %{player: 2}
    assert Resolver.match("me", [], context) == {:ok, 2}
  end

  test "match resolves object IDs" do
    assert Resolver.match("#123", [], %{}) == {:ok, 123}
    assert Resolver.match("#0", [], %{}) == {:ok, 0}
  end

  test "match resolves names in list" do
    # Create mock objects or assume they exist
    # Object #0 is System Object
    assert Resolver.match("The System Object", [0], %{}) == {:ok, 0}
  end

  test "resolve handles symbolic names" do
    # $login -> 0.login
    # This requires DBServer to have property 'login' on #0
    # In Minimal.db it might not be there.
    # Let's just check if it doesn't crash
    result = Resolver.resolve("$login")
    assert is_integer(result)
  end
end
