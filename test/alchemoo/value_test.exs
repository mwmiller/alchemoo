defmodule Alchemoo.ValueTest do
  use ExUnit.Case
  alias Alchemoo.Value

  test "creates number values" do
    assert Value.num(42) == {:num, 42}
    assert Value.typeof(Value.num(42)) == :num
  end

  test "creates string values" do
    assert Value.str("hello") == {:str, "hello"}
    assert Value.typeof(Value.str("hello")) == :str
  end

  test "creates object references" do
    assert Value.obj(123) == {:obj, 123}
    assert Value.typeof(Value.obj(123)) == :obj
  end

  test "creates list values" do
    list = Value.list([Value.num(1), Value.num(2)])
    assert list == {:list, [{:num, 1}, {:num, 2}]}
    assert Value.typeof(list) == :list
  end

  test "truthiness" do
    assert Value.truthy?(Value.num(1)) == true
    assert Value.truthy?(Value.num(0)) == false
    assert Value.truthy?(Value.str("")) == false
    assert Value.truthy?(Value.list([])) == false
    assert Value.truthy?(Value.err(:E_PERM)) == false
  end

  test "equality" do
    assert Value.equal?(Value.num(42), Value.num(42)) == true
    assert Value.equal?(Value.num(42), Value.num(43)) == false
    assert Value.equal?(Value.num(42), Value.str("42")) == false
  end

  test "string length" do
    assert Value.length(Value.str("hello")) == {:ok, {:num, 5}}
  end

  test "list length" do
    list = Value.list([Value.num(1), Value.num(2), Value.num(3)])
    assert Value.length(list) == {:ok, {:num, 3}}
  end

  test "string indexing" do
    str = Value.str("hello")
    assert Value.index(str, Value.num(1)) == {:ok, {:str, "h"}}
    assert Value.index(str, Value.num(5)) == {:ok, {:str, "o"}}
    assert Value.index(str, Value.num(6)) == {:error, :E_RANGE}
  end

  test "list indexing" do
    list = Value.list([Value.num(10), Value.num(20), Value.num(30)])
    assert Value.index(list, Value.num(1)) == {:ok, {:num, 10}}
    assert Value.index(list, Value.num(3)) == {:ok, {:num, 30}}
    assert Value.index(list, Value.num(4)) == {:error, :E_RANGE}
  end

  test "concatenation" do
    assert Value.concat(Value.str("hello"), Value.str(" world")) == {:str, "hello world"}

    list1 = Value.list([Value.num(1)])
    list2 = Value.list([Value.num(2)])
    assert Value.concat(list1, list2) == {:list, [{:num, 1}, {:num, 2}]}
  end

  test "to_literal conversion" do
    assert Value.to_literal(Value.num(42)) == "42"
    assert Value.to_literal(Value.obj(123)) == "#123"
    assert Value.to_literal(Value.str("hello")) == "hello"
    assert Value.to_literal(Value.list([Value.num(1), Value.num(2)])) == "{1, 2}"
  end
end
