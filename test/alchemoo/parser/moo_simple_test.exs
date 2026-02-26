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

    assert %AST.Block{
             statements: [%AST.ExprStmt{expr: %AST.Assignment{target: %AST.Var{name: "x"}}}]
           } = ast
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
            {:ok, _val, new_env} -> new_env
            {:error, _} -> env
          end
        end)
      catch
        {:return, val} -> val
      end

    assert result == Value.num(30)
  end

  test "parses and executes for numeric range" do
    code = """
    sum = 0;
    for i in [1..3]
      sum = sum + i;
    endfor
    return sum;
    """

    {:ok, %AST.Block{statements: stmts}} = MOOSimple.parse(code)

    result =
      try do
        Enum.reduce(stmts, %{}, fn stmt, env ->
          case Interpreter.eval(stmt, env) do
            {:ok, _val, new_env} -> new_env
            {:error, _} -> env
          end
        end)
      catch
        {:return, val} -> val
      end

    assert result == Value.num(6)
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

  test "parses LambdaCore login fallback verb with dollar range" do
    code = """
    if ((caller != #0) && (caller != this))
      return E_PERM;
    else
      clist = {};
      for j in ({this, @$object_utils:ancestors(this)})
        for i in [1..length(verbs(j))]
          if ((verb_args(j, i) == {"any", "none", "any"}) && index((info = verb_info(j, i))[2], "x"))
            vname = $string_utils:explode(info[3])[1];
            star = index(vname + "*", "*");
            clist = {@clist, $string_utils:uppercase(vname[1..star - 1]) + strsub(vname[star..$], "*", "")};
          endif
        endfor
      endfor
      return 0;
    endif
    """

    assert {:ok, %AST.Block{statements: [%AST.If{}]}} = MOOSimple.parse(code)
  end

  test "parses modulo inside nested parens in function args" do
    code = """
    notify(player, ("****  WARNING:  The server will shut down in " + $time_utils:english_time(when - (when % 60))) + ".");
    """

    assert {:ok, %AST.Block{statements: [%AST.ExprStmt{}]}} = MOOSimple.parse(code)
  end

  test "parses unary minus on non-literal expressions" do
    code = """
    x = -pair[2];
    """

    assert {:ok, %AST.Block{statements: [%AST.ExprStmt{}]}} = MOOSimple.parse(code)
  end

  test "parses catch with multiple error codes" do
    code = """
    while (E_VERBNF == (info = `verb_info(object, verbname) ! E_VERBNF, E_INVARG'))
      object = parent(object);
    endwhile
    """

    assert {:ok, %AST.Block{statements: [%AST.While{}]}} = MOOSimple.parse(code)
  end

  test "parses scientific float literals" do
    code = """
    x = 1e+24;
    """

    assert {:ok, %AST.Block{statements: [%AST.ExprStmt{}]}} = MOOSimple.parse(code)
  end

  test "does not treat try_ variable as try block opener" do
    code = """
    if (word in set)
      try_ = {@try_, word};
    endif
    """

    assert {:ok, %AST.Block{statements: [%AST.If{}]}} = MOOSimple.parse(code)
  end
end
