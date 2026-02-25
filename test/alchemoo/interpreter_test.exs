defmodule Alchemoo.InterpreterTest do
  use ExUnit.Case
  alias Alchemoo.Interpreter
  alias Alchemoo.Parser.Expression
  alias Alchemoo.Value

  defp eval(code) do
    {:ok, ast, _} = Expression.parse(code)

    case Interpreter.eval(ast) do
      {:ok, val, _env} -> {:ok, val}
      error -> error
    end
  end

  test "evaluates number literals" do
    assert eval("42") == {:ok, Value.num(42)}
    assert eval("-10") == {:ok, Value.num(-10)}
  end

  test "evaluates string literals" do
    assert eval("\"hello\"") == {:ok, Value.str("hello")}
  end

  test "evaluates object references" do
    assert eval("#123") == {:ok, Value.obj(123)}
  end

  test "evaluates arithmetic" do
    assert eval("1 + 2") == {:ok, Value.num(3)}
    assert eval("10 - 3") == {:ok, Value.num(7)}
    assert eval("4 * 5") == {:ok, Value.num(20)}
    assert eval("20 / 4") == {:ok, Value.num(5)}
  end

  test "evaluates complex expressions" do
    assert eval("2 + 3 * 4") == {:ok, Value.num(14)}
    assert eval("(2 + 3) * 4") == {:ok, Value.num(20)}
  end

  test "evaluates comparisons" do
    assert eval("5 == 5") == {:ok, Value.num(1)}
    assert eval("5 == 6") == {:ok, Value.num(0)}
    assert eval("5 != 6") == {:ok, Value.num(1)}
  end

  test "evaluates list literals" do
    assert {:ok, result} = eval("{1, 2, 3}")
    assert result == Value.list([Value.num(1), Value.num(2), Value.num(3)])
  end

  test "evaluates empty list" do
    assert {:ok, result} = eval("{}")
    assert result == Value.list([])
  end

  test "handles division by zero" do
    assert eval("10 / 0") == {:error, Value.err(:E_DIV)}
  end

  test "evaluates with variables" do
    {:ok, ast, _} = Expression.parse("x + 10")
    env = %{"x" => Value.num(5)}

    case Interpreter.eval(ast, env) do
      {:ok, val, _env} -> assert val == Value.num(15)
      error -> flunk("Expected {:ok, Value.num(15), ...}, got #{inspect(error)}")
    end
  end

  test "handles undefined variables" do
    {:ok, ast, _} = Expression.parse("undefined_var")
    assert Interpreter.eval(ast, %{}) == {:error, Value.err(:E_VARNF)}
  end
end
