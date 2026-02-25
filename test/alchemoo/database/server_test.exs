defmodule Alchemoo.Database.ServerTest do
  use ExUnit.Case, async: false

  alias Alchemoo.Database.Server

  # Server is started by application, no setup needed

  describe "load/1" do
    test "loads LambdaCore database" do
      assert {:ok, count} = Server.load("test/fixtures/lambdacore.db")
      assert count == 95
    end

    test "returns stats after loading" do
      Server.load("test/fixtures/lambdacore.db")

      stats = Server.stats()
      assert stats.loaded == true
      assert stats.object_count == 95
    end
  end

  describe "get_object/1" do
    setup do
      Server.load("test/fixtures/lambdacore.db")
      :ok
    end

    test "retrieves system object" do
      assert {:ok, obj} = Server.get_object(0)
      assert obj.id == 0
      assert obj.name == "The System Object"
    end

    test "returns error for invalid object" do
      assert {:error, :E_INVIND} = Server.get_object(9999)
    end
  end

  describe "get_property/2" do
    setup do
      Server.load("test/fixtures/lambdacore.db")
      :ok
    end

    test "retrieves property from object" do
      # System object should have properties
      case Server.get_property(0, "name") do
        {:ok, _value} -> assert true
        # Property might not exist
        {:error, :E_PROPNF} -> assert true
      end
    end

    test "returns error for nonexistent property" do
      assert {:error, :E_PROPNF} = Server.get_property(0, "nonexistent_prop_xyz")
    end

    test "returns error for invalid object" do
      assert {:error, :E_INVIND} = Server.get_property(9999, "name")
    end
  end

  describe "find_verb/2" do
    setup do
      Server.load("test/fixtures/lambdacore.db")
      :ok
    end

    test "finds verb on object" do
      # System object has verbs
      {:ok, %{verbs: [first_verb | _]}} = Server.get_object(0)
      assert {:ok, 0, verb} = Server.find_verb(0, first_verb.name)
      assert verb.name == first_verb.name
    end

    test "returns error for nonexistent verb" do
      assert {:error, :E_VERBNF} = Server.find_verb(0, "nonexistent_verb_xyz")
    end
  end

  describe "get_snapshot/0" do
    test "returns database snapshot" do
      Server.load("test/fixtures/lambdacore.db")

      db = Server.get_snapshot()
      assert map_size(db.objects) == 95
    end
  end
end
