defmodule Alchemoo.BuiltinsTest do
  use ExUnit.Case
  alias Alchemoo.Builtins
  alias Alchemoo.Value

  test "typeof returns correct type codes" do
    assert Builtins.call(:typeof, [Value.num(42)]) == Value.num(0)
    assert Builtins.call(:typeof, [Value.obj(1)]) == Value.num(1)
    assert Builtins.call(:typeof, [Value.str("hi")]) == Value.num(2)
    assert Builtins.call(:typeof, [Value.err(:E_PERM)]) == Value.num(3)
    assert Builtins.call(:typeof, [Value.list([])]) == Value.num(4)
  end

  test "tostr converts values to strings" do
    assert Builtins.call(:tostr, [Value.num(42)]) == Value.str("42")

    assert Builtins.call(:tostr, [Value.str("hello"), Value.str(" world")]) ==
             Value.str("hello world")
  end

  test "toint converts to integers" do
    assert Builtins.call(:toint, [Value.str("42")]) == Value.num(42)
    assert Builtins.call(:toint, [Value.num(42)]) == Value.num(42)
    assert Builtins.call(:toint, [Value.obj(5)]) == Value.num(5)
  end

  test "length returns correct lengths" do
    assert Builtins.call(:length, [Value.str("hello")]) == Value.num(5)
    assert Builtins.call(:length, [Value.list([Value.num(1), Value.num(2)])]) == Value.num(2)
  end

  test "listappend adds to list" do
    list = Value.list([Value.num(1), Value.num(2)])
    result = Builtins.call(:listappend, [list, Value.num(3)])
    assert result == Value.list([Value.num(1), Value.num(2), Value.num(3)])
  end

  test "listdelete removes from list" do
    list = Value.list([Value.num(1), Value.num(2), Value.num(3)])
    result = Builtins.call(:listdelete, [list, Value.num(2)])
    assert result == Value.list([Value.num(1), Value.num(3)])
  end

  test "is_member checks membership" do
    list = Value.list([Value.num(1), Value.num(2), Value.num(3)])
    assert Builtins.call(:is_member, [Value.num(2), list]) == Value.num(1)
    assert Builtins.call(:is_member, [Value.num(5), list]) == Value.num(0)
  end

  test "min and max work" do
    assert Builtins.call(:min, [Value.num(5), Value.num(2), Value.num(8)]) == Value.num(2)
    assert Builtins.call(:max, [Value.num(5), Value.num(2), Value.num(8)]) == Value.num(8)
  end

  test "abs returns absolute value" do
    assert Builtins.call(:abs, [Value.num(-5)]) == Value.num(5)
    assert Builtins.call(:abs, [Value.num(5)]) == Value.num(5)
  end

  test "time returns timestamp" do
    {:num, t} = Builtins.call(:time, [])
    assert t > 0
  end

  test "index finds substring" do
    assert Builtins.call(:index, [Value.str("hello"), Value.str("ll")]) == Value.num(3)
    assert Builtins.call(:index, [Value.str("hello"), Value.str("x")]) == Value.num(0)
    assert Builtins.call(:index, [Value.str("世界"), Value.str("界")]) == Value.num(2)
  end

  test "rindex finds rightmost substring" do
    assert Builtins.call(:rindex, [Value.str("hello hello"), Value.str("hello")]) == Value.num(7)
    assert Builtins.call(:rindex, [Value.str("hello"), Value.str("ll")]) == Value.num(3)
    assert Builtins.call(:rindex, [Value.str("hello"), Value.str("x")]) == Value.num(0)
    assert Builtins.call(:rindex, [Value.str("世界"), Value.str("界")]) == Value.num(2)

    assert Builtins.call(:rindex, [Value.str("abcabc"), Value.str("ABC"), Value.num(0)]) ==
             Value.num(4)
  end

  test "strsub replaces substring" do
    {:str, result} =
      Builtins.call(:strsub, [Value.str("hello"), Value.str("ll"), Value.str("rr")])

    assert result == "herro"
  end

  test "strcmp compares strings" do
    assert Builtins.call(:strcmp, [Value.str("a"), Value.str("b")]) == Value.num(-1)
    assert Builtins.call(:strcmp, [Value.str("b"), Value.str("a")]) == Value.num(1)
    assert Builtins.call(:strcmp, [Value.str("a"), Value.str("a")]) == Value.num(0)
  end

  test "explode splits string" do
    {:list, parts} = Builtins.call(:explode, [Value.str("a b c")])
    assert parts == [Value.str("a"), Value.str("b"), Value.str("c")]
  end

  test "valid checks if object exists" do
    assert Builtins.call(:valid, [Value.obj(0)]) == Value.num(1)
    assert Builtins.call(:valid, [Value.obj(9999)]) == Value.num(0)
  end

  test "max_object returns highest object number" do
    {:num, max} = Builtins.call(:max_object, [])
    assert max >= 0
  end

  test "player returns current player" do
    assert Builtins.call(:player, []) == Value.obj(2)
  end

  test "setadd adds value to list" do
    {:list, result} =
      Builtins.call(:setadd, [Value.list([Value.num(1), Value.num(2)]), Value.num(3)])

    assert result == [Value.num(1), Value.num(2), Value.num(3)]
  end

  test "setadd does not add duplicate" do
    {:list, result} =
      Builtins.call(:setadd, [Value.list([Value.num(1), Value.num(2)]), Value.num(2)])

    assert result == [Value.num(1), Value.num(2)]
  end

  test "setremove removes value from list" do
    {:list, result} =
      Builtins.call(:setremove, [
        Value.list([Value.num(1), Value.num(2), Value.num(3)]),
        Value.num(2)
      ])

    assert result == [Value.num(1), Value.num(3)]
  end

  test "setremove handles missing value" do
    {:list, result} =
      Builtins.call(:setremove, [Value.list([Value.num(1), Value.num(2)]), Value.num(3)])

    assert result == [Value.num(1), Value.num(2)]
  end

  test "sort sorts numbers" do
    {:list, result} =
      Builtins.call(:sort, [Value.list([Value.num(3), Value.num(1), Value.num(2)])])

    assert result == [Value.num(1), Value.num(2), Value.num(3)]
  end

  test "sort sorts strings" do
    {:list, result} =
      Builtins.call(:sort, [Value.list([Value.str("c"), Value.str("a"), Value.str("b")])])

    assert result == [Value.str("a"), Value.str("b"), Value.str("c")]
  end

  test "sort sorts mixed types" do
    {:list, result} =
      Builtins.call(:sort, [Value.list([Value.str("a"), Value.num(1), Value.obj(2)])])

    assert result == [Value.num(1), Value.obj(2), Value.str("a")]
  end

  test "verbs lists verb names" do
    {:list, verbs} = Builtins.call(:verbs, [Value.obj(2)])
    assert is_list(verbs)
  end

  test "verb_code returns code lines" do
    # Assuming object #2 has some verbs
    result = Builtins.call(:verb_code, [Value.obj(2), Value.str("test")])
    # Will be E_VERBNF if verb doesn't exist, or a list if it does
    assert match?({:list, _}, result) or match?({:err, :E_VERBNF}, result)
  end

  test "match finds patterns" do
    # Basic match
    result = Builtins.call(:match, [Value.str("hello world"), Value.str("world")])
    assert {:list, [{:num, 7}, {:num, 12}, {:list, _}, {:str, "world"}]} = result

    # Failed match
    assert Builtins.call(:match, [Value.str("hello"), Value.str("xyz")]) == Value.list([])

    # Captures
    result = Builtins.call(:match, [Value.str("foo 123 bar"), Value.str("foo %([0-9]+%) bar")])
    {:list, [{:num, 1}, {:num, 12}, {:list, captures}, {:str, "foo 123 bar"}]} = result
    assert Enum.at(captures, 0) == Value.list([Value.num(5), Value.num(7)])

    # Case insensitive
    result = Builtins.call(:match, [Value.str("HELLO"), Value.str("hello"), Value.num(0)])
    assert {:list, [{:num, 1}, {:num, 6}, _, _]} = result
  end

  test "rmatch finds rightmost pattern" do
    result = Builtins.call(:rmatch, [Value.str("abc abc abc"), Value.str("abc")])
    assert {:list, [{:num, 9}, {:num, 12}, _, _]} = result
  end

  test "substitute performs replacements" do
    subs = Builtins.call(:match, [Value.str("foo 123 bar"), Value.str("foo %([0-9]+%) bar")])
    result = Builtins.call(:substitute, [Value.str("The number is %1 (full: %0) %%"), subs])
    assert result == Value.str("The number is 123 (full: foo 123 bar) %")
  end

  test "verb_args and set_verb_args" do
    # Wizard object #2 has 'test' verb? No, let's use object #0 and 'do_login_command'
    obj = Value.obj(0)
    verb = Value.str("do_login_command")

    # Get current args
    {:list, args} = Builtins.call(:verb_args, [obj, verb])
    assert length(args) == 3

    # Set new args
    assert Builtins.call(:set_verb_args, [
             obj,
             verb,
             Value.list([Value.str("any"), Value.str("none"), Value.str("any")])
           ]) == Value.num(0)

    # Verify
    assert Builtins.call(:verb_args, [obj, verb]) ==
             Value.list([Value.str("any"), Value.str("none"), Value.str("any")])
  end

  test "is_clear_property detects inherited value" do
    # Object #0 is a root, so properties aren't clear usually.
    # But we can set one to clear.
    obj = Value.obj(0)
    prop = Value.str("builder")

    Builtins.call(:clear_property, [obj, prop])
    assert Builtins.call(:is_clear_property, [obj, prop]) == Value.num(1)
  end

  test "is_player checks USER flag" do
    # Object #2 is wizard, should be a player
    assert Builtins.call(:is_player, [Value.obj(2)]) == Value.num(1)
    # Object #0 is system object, should NOT be a player
    assert Builtins.call(:is_player, [Value.obj(0)]) == Value.num(0)
  end

  test "players returns list of all players" do
    {:list, players} = Builtins.call(:players, [])
    assert is_list(players)
    assert Value.obj(2) in players
  end

  test "memory_usage returns a number" do
    {:num, usage} = Builtins.call(:memory_usage, [])
    assert usage > 0
  end

  test "extended math functions work" do
    # These return scaled integers (x1000)
    assert Builtins.call(:tan, [Value.num(0)]) == Value.num(0)
    assert Builtins.call(:exp, [Value.num(0)]) == Value.num(1000)
    assert Builtins.call(:log, [Value.num(1)]) == Value.num(0)
    assert Builtins.call(:log10, [Value.num(10)]) == Value.num(1000)

    # identity functions for integers
    assert Builtins.call(:ceil, [Value.num(5)]) == Value.num(5)
    assert Builtins.call(:floor, [Value.num(5)]) == Value.num(5)
    assert Builtins.call(:trunc, [Value.num(5)]) == Value.num(5)

    # hyperbolic
    assert Builtins.call(:sinh, [Value.num(0)]) == Value.num(0)
    assert Builtins.call(:cosh, [Value.num(0)]) == Value.num(1000)
    assert Builtins.call(:tanh, [Value.num(0)]) == Value.num(0)
  end

  test "tonum is alias for toint" do
    assert Builtins.call(:tonum, [Value.str("42")]) == Value.num(42)
  end

  test "crypt and binary_hash" do
    {:str, hash1} = Builtins.call(:crypt, [Value.str("password"), Value.str("ab")])
    {:str, hash2} = Builtins.call(:crypt, [Value.str("password"), Value.str("ab")])
    assert hash1 == hash2

    {:str, sha1} = Builtins.call(:binary_hash, [Value.str("hello")])
    assert String.length(sha1) == 40
  end

  test "binary encoding and decoding" do
    # Encode newline
    {:str, encoded} = Builtins.call(:encode_binary, [Value.str("a\nb")])
    assert encoded =~ "~0A"

    # Decode it back
    assert Builtins.call(:decode_binary, [Value.str(encoded)]) == Value.str("a\nb")

    # Literal ~
    assert Builtins.call(:encode_binary, [Value.str("a~b")]) == Value.str("a~~b")
    assert Builtins.call(:decode_binary, [Value.str("a~~b")]) == Value.str("a~b")
  end

  test "connection built-ins return error for invalid player" do
    assert Builtins.call(:idle_seconds, [Value.obj(999)]) == Value.err(:E_INVARG)
    assert Builtins.call(:connected_seconds, [Value.obj(999)]) == Value.err(:E_INVARG)
    assert Builtins.call(:boot_player, [Value.obj(999)]) == Value.num(0)
  end

  test "task_id returns a number" do
    # When no context, it defaults to 0
    assert Builtins.call(:task_id, []) == Value.num(0)

    # When context is set
    Process.put(:task_context, %{id: make_ref()})
    {:num, id} = Builtins.call(:task_id, [])
    assert id > 0
    Process.delete(:task_context)
  end

  test "call_function dynamically calls built-ins" do
    # Call tostr(42) via call_function
    result = Builtins.call(:call_function, [Value.str("tostr"), Value.num(42)])
    assert result == Value.str("42")

    # Call with error
    assert Builtins.call(:call_function, [Value.str("invalid")]) == Value.err(:E_VERBNF)
  end

  test "eval evaluates MOO code" do
    # Eval simple expression
    result = Builtins.call(:eval, [Value.str("return 2 + 2;")])
    assert result == Value.list([Value.num(1), Value.num(4)])

    # Eval with error
    result = Builtins.call(:eval, [Value.str("invalid syntax")])
    assert match?({:list, [{:num, 0}, {:str, _}]}, result)
  end

  test "security built-ins" do
    # Initial context
    Process.put(:task_context, %{
      player: 2,
      this: 0,
      caller: -1,
      perms: 2,
      caller_perms: 0,
      stack: []
    })

    assert Builtins.call(:caller_perms, []) == Value.obj(0)
    assert Builtins.call(:player, []) == Value.obj(2)

    # set_task_perms
    assert Builtins.call(:set_task_perms, [Value.obj(100)]) == Value.num(1)
    assert Builtins.call(:player, []) == Value.obj(100)
    
    # callers() - empty initially
    assert Builtins.call(:callers, []) == Value.list([])

    # callers() - with stack
    Process.put(:task_context, %{
      player: 100,
      this: 10,
      caller: 0,
      perms: 100,
      caller_perms: 2,
      stack: [
        %{this: 0, verb_name: "test", verb_owner: 2, player: 2}
      ]
    })

    {:list, [caller_info]} = Builtins.call(:callers, [])
    assert caller_info == Value.list([
      Value.obj(0),
      Value.str("test"),
      Value.obj(2),
      Value.obj(2)
    ])

    {:list, [{:num, 1}, {:list, stack}]} = Builtins.call(:eval, [Value.str("return callers();")])
    assert length(stack) == 1
    assert Enum.at(stack, 0) == caller_info

    Process.delete(:task_context)
  end

  test "database and misc built-ins" do
    # floatstr
    assert Builtins.call(:floatstr, [Value.num(1234), Value.num(2)]) == Value.str("1.23")
    assert Builtins.call(:floatstr, [Value.num(500), Value.num(1)]) == Value.str("0.5")

    # set_player_flag
    obj = Value.obj(0)
    # Check initial (should be 0)
    assert Builtins.call(:is_player, [obj]) == Value.num(0)
    # Set it
    assert Builtins.call(:set_player_flag, [obj, Value.num(1)]) == Value.num(1)
    assert Builtins.call(:is_player, [obj]) == Value.num(1)
    # Clear it
    assert Builtins.call(:set_player_flag, [obj, Value.num(0)]) == Value.num(1)
    assert Builtins.call(:is_player, [obj]) == Value.num(0)

    # db_disk_size
    {:num, size} = Builtins.call(:db_disk_size, [])
    assert size >= 0

    # dump_database
    # Mocking check: assumes Checkpoint.Server is running or fails gracefully
    result = Builtins.call(:dump_database, [])
    assert result in [Value.num(1), Value.num(0)]

    # queue_info
    {:list, ids} = Builtins.call(:queue_info, [])
    assert is_list(ids)
  end

  test "introspection built-ins" do
    # function_info
    {:list, info} = Builtins.call(:function_info, [Value.str("tostr")])
    assert length(info) == 3
    
    # disassemble (mocked as source code return)
    # Use object #0 and a known verb if possible, or expect error/empty
    # Assuming object #0 exists
    result = Builtins.call(:disassemble, [Value.obj(0), Value.str("invalid_verb")])
    assert result == Value.err(:E_VERBNF)
  end

  test "network built-ins" do
    # listen/unlisten currently return E_PERM
    assert Builtins.call(:listen, [Value.obj(0), Value.num(8080)]) == Value.err(:E_PERM)
    assert Builtins.call(:unlisten, [Value.num(8080)]) == Value.err(:E_PERM)
    assert Builtins.call(:open_network_connection, [Value.str("google.com"), Value.num(80)]) == Value.err(:E_PERM)
  end
end
