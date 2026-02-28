defmodule Alchemoo.MOOExceptionTest do
  use ExUnit.Case
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Interpreter
  alias Alchemoo.Parser.MOOSimple
  alias Alchemoo.Runtime
  alias Alchemoo.Value

  setup do
    :ok
  end

  defp run(code, env \\ %{}) do
    runtime = Runtime.new(DB.get_snapshot())

    # Standard MOO environment setup
    env =
      env
      |> Map.put_new(:runtime, runtime)
      |> Map.put_new("INT", Value.num(0))
      |> Map.put_new("NUM", Value.num(0))
      |> Map.put_new("OBJ", Value.num(1))
      |> Map.put_new("STR", Value.num(2))
      |> Map.put_new("ERR", Value.num(3))
      |> Map.put_new("LIST", Value.num(4))
      |> Map.put_new("E_NONE", Value.err(:E_NONE))
      |> Map.put_new("E_TYPE", Value.err(:E_TYPE))
      |> Map.put_new("E_DIV", Value.err(:E_DIV))
      |> Map.put_new("E_PERM", Value.err(:E_PERM))
      |> Map.put_new("E_PROPNF", Value.err(:E_PROPNF))
      |> Map.put_new("E_VERBNF", Value.err(:E_VERBNF))
      |> Map.put_new("E_VARNF", Value.err(:E_VARNF))
      |> Map.put_new("E_INVIND", Value.err(:E_INVIND))
      |> Map.put_new("E_RECMOVE", Value.err(:E_RECMOVE))
      |> Map.put_new("E_MAXREC", Value.err(:E_MAXREC))
      |> Map.put_new("E_RANGE", Value.err(:E_RANGE))
      |> Map.put_new("E_ARGS", Value.err(:E_ARGS))
      |> Map.put_new("E_NACC", Value.err(:E_NACC))
      |> Map.put_new("E_INVARG", Value.err(:E_INVARG))
      |> Map.put_new("E_QUOTA", Value.err(:E_QUOTA))
      |> Map.put_new("E_FLOAT", Value.err(:E_FLOAT))
      |> Map.put_new("ANY", :ANY)

    {:ok, ast} = MOOSimple.parse(code)

    try do
      case Interpreter.eval(ast, env) do
        {:ok, val, _new_env} -> {:ok, val}
        {:error, err, _env} -> {:error, err}
      end
    catch
      {:return, val} -> {:ok, val}
      {:error, err, _env} -> {:error, err}
      {:error, err} -> {:error, err}
    end
  end

  test "standard try-except with built-in error" do
    code = """
    try
      result = verb_info(#0, "nonexistent");
      return "succeeded";
    except (E_VERBNF)
      return "caught";
    endtry
    """

    assert run(code) == {:ok, Value.str("caught")}
  end

  test "try-except with ANY" do
    code = """
    try
      1 / 0;
    except (ANY)
      return "caught all";
    endtry
    """

    assert run(code) == {:ok, Value.str("caught all")}
  end

  test "try-except with variable capture" do
    code = """
    try
      1 / 0;
    except err (E_DIV)
      return err[1];
    endtry
    """

    assert run(code) == {:ok, Value.err(:E_DIV)}
  end

  test "raise() built-in triggers except" do
    code = """
    try
      raise(E_PERM);
    except (E_PERM)
      return "caught raise";
    endtry
    """

    assert run(code) == {:ok, Value.str("caught raise")}
  end

  test "catch expression (expr ! codes => default)" do
    # Standard catch
    assert run("return (1 / 0) ! E_DIV => 42;") == {:ok, Value.num(42)}

    # Catch ANY
    assert run("return (1 / 0) ! ANY => 7;") == {:ok, Value.num(7)}

    # Nested catch
    assert run("return ((1 / 0) ! E_PERM => 1) ! E_DIV => 2;") == {:ok, Value.num(2)}
  end

  test "unhandled error propagates" do
    code = """
    try
      1 / 0;
    except (E_PERM)
      return "wrong";
    endtry
    """

    assert run(code) == {:error, Value.err(:E_DIV)}
  end

  test "verb returning error value does NOT trigger catch" do
    # Mock a verb that returns E_PERM as a value
    # We'll use a built-in that we know returns E_PERM in certain cases
    # Actually, let's just use eval() to return an error value
    code = """
    x = E_PERM;
    try
      return x;
    except (E_PERM)
      return "should not catch";
    endtry
    """

    assert run(code) == {:ok, Value.err(:E_PERM)}
  end

  test "complex core-like confunc logic" do
    code = """
    try
      raise(E_VERBNF, "Verb not found", 0);
    except id (ANY)
      return id[2];
    endtry
    """

    # id[2] should be the string representation of the error code
    assert run(code) == {:ok, Value.str("E_VERBNF")}
  end

  test "standard try-finally" do
    code = """
    x = 0;
    try
      x = 1;
    finally
      x = 2;
    endtry
    return x;
    """

    assert run(code) == {:ok, Value.num(2)}
  end

  test "finally runs after exception" do
    code = """
    x = 0;
    try
      try
        1 / 0;
      finally
        x = 42;
      endtry
    except (ANY)
      return x;
    endtry
    """

    assert run(code) == {:ok, Value.num(42)}
  end
end
