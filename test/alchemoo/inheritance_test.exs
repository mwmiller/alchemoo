defmodule Alchemoo.InheritanceTest do
  use ExUnit.Case
  alias Alchemoo.Database.{Object, Verb}
  alias Alchemoo.Runtime
  alias Alchemoo.Value

  setup do
    # Parent object #1
    parent = %Object{
      id: 1,
      name: "parent",
      parent: -1,
      verbs: [
        %Verb{
          name: "test",
          code: ["return \"parent\";"],
          owner: 2,
          perms: "rx",
          args: {:none, :none, :none}
        }
      ],
      properties: [],
      contents: [2]
    }

    # Child object #2
    child = %Object{
      id: 2,
      name: "child",
      parent: 1,
      verbs: [
        %Verb{
          name: "test",
          code: ["return pass();"],
          owner: 2,
          perms: "rx",
          args: {:none, :none, :none}
        }
      ],
      properties: [],
      location: 1,
      contents: []
    }

    objects = %{1 => parent, 2 => child}
    db = %Alchemoo.Database{objects: objects}
    runtime = Runtime.new(db)

    {:ok, runtime: runtime}
  end

  test "inheritance finds parent verb", %{runtime: runtime} do
    # Call #2:test() which is not defined on #2? No, I defined it above.
    # Wait, if I call #2:test() and it's on #2, it runs #2's code.
    # If I call #2:test() and it's NOT on #2, it runs #1's code.

    # Test 1: Simple inheritance (verb only on parent)
    parent_only_verb = %Verb{
      name: "parent_verb",
      code: ["return 42;"],
      owner: 2,
      perms: "rx",
      args: {:none, :none, :none}
    }

    runtime = update_in(runtime.objects[1].verbs, &[parent_only_verb | &1])

    assert {:ok, Value.num(42)} ==
             Runtime.call_verb(runtime, Value.obj(2), "parent_verb", [], %{})
  end

  test "pass() calls parent verb", %{runtime: runtime} do
    # Call #2:test() which calls pass()
    assert {:ok, Value.str("parent")} == Runtime.call_verb(runtime, Value.obj(2), "test", [], %{})
  end
end
