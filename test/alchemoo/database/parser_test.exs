defmodule Alchemoo.Database.ParserTest do
  use ExUnit.Case
  alias Alchemoo.Database.Parser

  test "parses Minimal.db format" do
    {:ok, db} = Parser.parse_file("/tmp/Minimal.db")

    assert db.version == 1
    assert db.object_count == 4
    assert map_size(db.objects) == 4

    # Check System Object (#0)
    system = db.objects[0]
    assert system.name == "System Object"
    assert system.id == 0
    assert length(system.verbs) == 1

    # Check verb has code
    [verb] = system.verbs
    assert verb.name == "do_login_command"
    assert length(verb.code) == 1
    assert hd(verb.code) == "return #3;"
  end
end
