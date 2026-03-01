defmodule Alchemoo.Parser.VectorsTest do
  use ExUnit.Case
  alias Alchemoo.Parser.Program

  @vectors [
    # 1. Basic if
    """
    if (1)
      return 1;
    endif
    """,
    # 2. if-else
    """
    if (1)
      return 1;
    else
      return 0;
    endif
    """,
    # 3. if-elseif-else
    """
    if (1)
      return 1;
    elseif (2)
      return 2;
    else
      return 3;
    endif
    """,
    # 4. Nested if
    """
    if (1)
      if (2)
        return 2;
      endif
      return 1;
    endif
    """,
    # 5. for loop list
    """
    for x in ({1, 2, 3})
      player:tell(x);
    endfor
    """,
    # 6. for loop range
    """
    for i in [1..10]
      player:tell(i);
    endfor
    """,
    # 7. while loop
    """
    while (x < 10)
      x = x + 1;
    endwhile
    """,
    # 8. try-except
    """
    try
      1 / 0;
    except (E_DIV)
      return 0;
    endtry
    """,
    # 9. try-finally
    """
    try
      foo();
    finally
      bar();
    endtry
    """,
    # 10. try-except-finally
    """
    try
      foo();
    except (ANY)
      log(error);
    finally
      cleanup();
    endtry
    """,
    # 11. Multiple excepts
    """
    try
      foo();
    except (E_VERBNF)
      return 1;
    except (E_PERM)
      return 2;
    except (ANY)
      return 3;
    endtry
    """,
    # 12. Complex conditions with #0
    """
    if (caller != #0)
      return E_PERM;
    endif
    """,
    # 13. Complex list splicing
    """
    clist = {@clist, $string_utils:uppercase(vname[1..star - 1]) + strsub(vname[star..$], "*", "")};
    """,
    # 14. Backtick catch
    """
    x = `1 / 0 ! ANY => 42';
    """,
    # 15. Property access with dollar
    """
    return $login:server_started();
    """,
    # 16. Scientific notation
    """
    x = 1.2e+10;
    y = -5e-2;
    """,
    # 17. break and continue
    """
    for i in [1..10]
      if (i == 5) continue; endif
      if (i == 8) break; endif
    endfor
    """,
    # 18. List destructuring with optional
    """
    {search, ?sofar = 0} = args;
    """,
    # 19. Parenthesized property access
    """
    object.(pn) = value;
    """,
    # 20. Parenthesized verb call
    """
    object:(verb_name)(args);
    """,
    # 21. Unary NOT collision
    """
    if (!string)
      return $nothing;
    endif
    """,
    # 22. Range with $
    """
    star = index(vname + "*", "*");
    vname = vname[1..star - 1];
    rest = vname[star..$];
    """,
    # 23. Multiple comments and blank lines
    """
    # Leading comment
    if (1)
      # Inner comment
      
      return 1; # End of line comment
    endif
    # Trailing comment
    """,
    # 24. Complex nested if-else with for (LambdaCore fallback)
    """
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
  ]

  test "parses all vectors correctly" do
    Enum.each(Enum.with_index(@vectors, 1), fn {code, idx} ->
      case Program.parse(code) do
        {:ok, _ast} -> :ok
        {:error, reason} ->
          flunk("Failed to parse vector ##{idx}:\n#{code}\nReason: #{inspect(reason)}")
      end
    end)
  end
end
