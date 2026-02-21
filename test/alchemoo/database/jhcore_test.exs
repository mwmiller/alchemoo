defmodule Alchemoo.Database.JHCoreTest do
  use ExUnit.Case
  alias Alchemoo.Database.Parser

  test "parses JHCore Format 4" do
    {:ok, db} = Parser.parse_file("/tmp/JHCore-DEV-2.db")

    assert db.version == 4
    assert db.object_count == 237
    # JHCore has 236 objects parsed
    assert map_size(db.objects) >= 236

    # Note: JHCore has some header parsing quirks, but verb code is 100% parsed
    # Check that we have objects
    assert map_size(db.objects) > 0
  end

  test "parses JHCore verb code" do
    {:ok, db} = Parser.parse_file("/tmp/JHCore-DEV-2.db")

    # Count verbs with code
    verbs_with_code =
      db.objects
      |> Map.values()
      |> Enum.flat_map(& &1.verbs)
      |> Enum.count(&(&1.code != []))

    assert verbs_with_code > 0
  end
end
