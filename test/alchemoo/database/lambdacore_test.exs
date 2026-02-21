defmodule Alchemoo.Database.LambdaCoreTest do
  use ExUnit.Case
  alias Alchemoo.Database.Parser

  test "parses LambdaCore Format 4" do
    {:ok, db} = Parser.parse_file("/tmp/LambdaCore-12Apr99.db")

    assert db.version == 4
    assert db.object_count == 95
    assert map_size(db.objects) == 95

    # Check System Object (#0)
    system = db.objects[0]
    assert system.name == "The System Object"
    assert system.id == 0
    assert system.owner == 2
    assert length(system.verbs) == 19
    assert length(system.properties) == 118

    # Check first verb
    [first_verb | _] = system.verbs
    assert first_verb.name == "do_login_command"
    assert first_verb.owner == 2

    # Check first property name
    [first_prop | _] = system.properties
    assert first_prop.name == "builder"
  end

  test "parses verb code from LambdaCore" do
    {:ok, db} = Parser.parse_file("/tmp/LambdaCore-12Apr99.db")

    # Check that #0:0 (do_login_command) has code
    system = db.objects[0]
    [first_verb | _] = system.verbs

    assert first_verb.name == "do_login_command"
    assert is_list(first_verb.code)
    assert first_verb.code != []

    # Check for specific code content
    code_text = Enum.join(first_verb.code, "\n")
    assert String.contains?(code_text, "callers()")
    assert String.contains?(code_text, "E_PERM")
  end

  test "parses multiple verb codes" do
    {:ok, db} = Parser.parse_file("/tmp/LambdaCore-12Apr99.db")

    # Check system object has multiple verbs with code
    system = db.objects[0]
    assert length(system.verbs) == 19

    # Check that multiple verbs have code
    verbs_with_code = Enum.count(system.verbs, fn v -> v.code != [] end)
    assert verbs_with_code > 10

    # Check second verb
    second_verb = Enum.at(system.verbs, 1)
    assert second_verb.name == "server_started"
    assert second_verb.code != []
  end
end
