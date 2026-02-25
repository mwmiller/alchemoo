defmodule Alchemoo.Database.ParserTest do
  use ExUnit.Case
  alias Alchemoo.Database.Parser

  test "parses LambdaCore format" do
    {:ok, db} = Parser.parse_file("test/fixtures/lambdacore.db")

    assert db.version == 4
    assert db.object_count == 95
    assert map_size(db.objects) == 95

    # Check System Object (#0)
    system = db.objects[0]
    assert system.id == 0
    assert system.verbs != []

    # Check verb has code
    verb = hd(system.verbs)
    assert verb.code != []
  end
end
