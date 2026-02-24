defmodule Alchemoo.Parser.MOOSimpleTest do
  use ExUnit.Case
  alias Alchemoo.{AST, Interpreter, Value}
  alias Alchemoo.Parser.MOOSimple

  test "parses simple return statement" do
    {:ok, ast} = MOOSimple.parse("return 42;")
    assert %AST.Block{statements: [%AST.Return{value: _}]} = ast
  end

  test "parses if statement" do
    code = """
    if (x > 5)
      return 1;
    endif
    """

    {:ok, ast} = MOOSimple.parse(code)
    assert %AST.Block{statements: [%AST.If{}]} = ast
  end

  test "parses while loop" do
    code = """
    while (x < 10)
      x = x + 1;
    endwhile
    """

    {:ok, ast} = MOOSimple.parse(code)
    assert %AST.Block{statements: [%AST.While{}]} = ast
  end

  test "parses for loop" do
    code = """
    for item in ({1, 2, 3})
      x = x + item;
    endfor
    """

    {:ok, ast} = MOOSimple.parse(code)
    assert %AST.Block{statements: [%AST.ForList{}]} = ast
  end

  test "parses assignment" do
    {:ok, ast} = MOOSimple.parse("x = 42;")
    assert %AST.Block{statements: [%AST.ExprStmt{expr: %AST.Assignment{target: %AST.Var{name: "x"}}}]} = ast
  end

  test "parses and executes simple verb" do
    code = """
    x = 10;
    y = 20;
    return x + y;
    """

    {:ok, %AST.Block{statements: stmts}} = MOOSimple.parse(code)

    # Execute statements
    result =
      try do
        Enum.reduce(stmts, %{}, fn stmt, env ->
          case Interpreter.eval(stmt, env) do
            {:ok, _, new_env} -> new_env
            {:ok, _val} -> env
            {:error, _} -> env
          end
        end)
      catch
        {:return, val} -> val
      end

    assert result == Value.num(30)
  end

  test "parses complex verb code" do
    code = """
    if (x > 5)
      return 1;
    else
      return 0;
    endif
    """

    {:ok, ast} = MOOSimple.parse(code)
    assert %AST.Block{statements: [%AST.If{else_block: %AST.Block{}}]} = ast
  end
end
