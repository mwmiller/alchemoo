defmodule Alchemoo.Parser.ProgramTest do
  use ExUnit.Case
  alias Alchemoo.{AST, Value}
  alias Alchemoo.Parser.Program

  test "parses simple return statement" do
    {:ok, %AST.Block{statements: stmts}} = Program.parse("return 42;")
    assert [%AST.Return{value: %AST.Literal{value: {:num, 42}}}] = stmts
  end

  test "parses if statement" do
    code = """
    if (1)
      return 1;
    endif
    """
    {:ok, %AST.Block{statements: stmts}} = Program.parse(code)
    assert [%AST.If{condition: %AST.Literal{value: {:num, 1}}, then_block: %AST.Block{}}] = stmts
  end

  test "parses if-else statement" do
    code = """
    if (1)
      return 1;
    else
      return 0;
    endif
    """
    {:ok, %AST.Block{statements: stmts}} = Program.parse(code)
    assert [%AST.If{else_block: %AST.Block{}}] = stmts
  end

  test "parses if-elseif statement" do
    code = """
    if (1)
      return 1;
    elseif (2)
      return 2;
    endif
    """
    {:ok, %AST.Block{statements: stmts}} = Program.parse(code)
    assert [%AST.If{elseif_blocks: [%AST.ElseIf{}]}] = stmts
  end

  test "parses nested if in else" do
    code = """
    if (1)
      return 1;
    else
      if (2)
        return 2;
      endif
      return 0;
    endif
    """
    assert {:ok, %AST.Block{statements: [%AST.If{else_block: %AST.Block{statements: [%AST.If{}, %AST.Return{}]}}]}} = Program.parse(code)
  end

  test "parses complex nested structure from LambdaCore" do
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
    assert {:ok, %AST.Block{statements: [%AST.If{}]}} = Program.parse(code)
  end

  test "parses try-except ANY" do
    code = """
    try
      1 / 0;
    except (ANY)
      return E_DIV;
    endtry
    """
    assert {:ok, %AST.Block{statements: [%AST.Try{except_clauses: [%AST.Except{codes: :ANY}]}]}} = Program.parse(code)
  end

  test "parses try with multiple except clauses" do
    code = """
    try
      foo();
    except (E_VERBNF)
      return 1;
    except (ANY)
      return 2;
    endtry
    """
    assert {:ok, %AST.Block{statements: [%AST.Try{except_clauses: [%AST.Except{}, %AST.Except{codes: :ANY}]}]}} = Program.parse(code)
  end

  test "parses while loop" do
    code = """
    while (1)
      return 1;
    endwhile
    """
    assert {:ok, %AST.Block{statements: [%AST.While{}]}} = Program.parse(code)
  end

  test "parses for-in-list loop" do
    code = """
    for x in ({1, 2, 3})
      return x;
    endfor
    """
    assert {:ok, %AST.Block{statements: [%AST.ForList{var: "x"}]}} = Program.parse(code)
  end

  test "parses for-range loop" do
    code = """
    for i in [1..10]
      return i;
    endfor
    """
    assert {:ok, %AST.Block{statements: [%AST.For{var: "i"}]}} = Program.parse(code)
  end

  test "parses scientific floats" do
    assert {:ok, %AST.Block{statements: [%AST.ExprStmt{expr: %AST.Literal{value: {:float, 1.0e24}}}]}} = Program.parse("1e+24;")
    assert {:ok, %AST.Block{statements: [%AST.ExprStmt{expr: %AST.Literal{value: {:float, -1.5e-10}}}]}} = Program.parse("-1.5e-10;")
  end

  test "parses backtick catch with ANY" do
    code = "`1 / 0 ! ANY => 42';"
    assert {:ok, %AST.Block{statements: [%AST.ExprStmt{expr: %AST.Catch{codes: :ANY}}]}} = Program.parse(code)
  end

  test "parses list destructuring with optional vars" do
    code = "{search, ?sofar = 0} = args;"
    assert {:ok, %AST.Block{statements: [%AST.ExprStmt{expr: %AST.Assignment{target: %AST.ListExpr{elements: [%AST.Var{}, %AST.OptionalVar{name: "sofar"}]}}}]}} = Program.parse(code)
  end

  test "strips end-of-line comments" do
    code = """
    x = 1; # this is a comment
    if (x) # another comment
      return x; # yet another
    endif # comment here
    """
    {:ok, %AST.Block{statements: stmts}} = Program.parse(code)
    assert [%AST.Assignment{}, %AST.If{}] = stmts
  end
end
