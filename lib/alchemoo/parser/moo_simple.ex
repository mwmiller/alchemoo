defmodule Alchemoo.Parser.MOOSimple do
  @moduledoc """
  Simplified MOO parser for verb code.

  Parses MOO statements line by line with basic syntax support.
  """

  alias Alchemoo.AST
  alias Alchemoo.Parser.Expression
  alias Alchemoo.Value

  @doc """
  Parse MOO verb code (list of lines) into AST.
  """
  def parse(lines) when is_list(lines) do
    cleaned =
      for line <- lines,
          trimmed = String.trim(line),
          not ignored_line?(trimmed) do
        trimmed
      end

    parse_statements(cleaned, [])
  end

  def parse(code) when is_binary(code) do
    code
    |> String.split("\n")
    |> parse()
  end

  defp ignored_line?(trimmed) do
    trimmed == "" or
      String.starts_with?(trimmed, "//") or
      (String.starts_with?(trimmed, "#") and not Regex.match?(~r/^#-?\d+/, trimmed))
  end

  defp parse_statements([], acc), do: {:ok, %AST.Block{statements: Enum.reverse(acc)}}

  defp parse_statements([line | rest], acc) do
    case parse_statement(line, rest) do
      {:ok, stmt, remaining} ->
        parse_statements(remaining, [stmt | acc])

      {:error, _} = err ->
        err
    end
  end

  defp parse_statement("if " <> cond_str, rest) do
    handle_if(cond_str, rest)
  end

  defp parse_statement("while " <> cond_str, rest) do
    handle_while(cond_str, rest)
  end

  defp parse_statement("for " <> for_str, rest) do
    handle_for(for_str, rest)
  end

  defp parse_statement("return" <> rest_str, rest) do
    handle_return(rest_str, rest)
  end

  defp parse_statement("break", rest) do
    {:ok, %AST.Break{}, rest}
  end

  defp parse_statement("break;", rest) do
    {:ok, %AST.Break{}, rest}
  end

  defp parse_statement("continue", rest) do
    {:ok, %AST.Continue{}, rest}
  end

  defp parse_statement("continue;", rest) do
    {:ok, %AST.Continue{}, rest}
  end

  defp parse_statement("try", rest) do
    handle_try(rest)
  end

  defp parse_statement(line, rest) do
    line = String.trim_trailing(line, ";")

    # Expression statement (including assignment)
    case Expression.parse(line) do
      {:ok, expr, _} -> {:ok, %AST.ExprStmt{expr: expr}, rest}
      err -> err
    end
  end

  defp handle_if(cond_str, rest) do
    cond_str = strip_parens(cond_str)

    case Expression.parse(cond_str) do
      {:ok, condition, _} ->
        {then_lines, remaining} = take_until(rest, ["elseif", "else", "endif"])

        case parse(then_lines) do
          {:ok, then_block} ->
            {elseif_blocks, remaining} = parse_elseif_blocks(remaining)
            parse_if_rest(condition, then_block, elseif_blocks, remaining)

          err ->
            err
        end

      err ->
        err
    end
  end

  defp parse_elseif_blocks(["elseif " <> cond_str | rest]) do
    cond_str = strip_parens(cond_str)

    case Expression.parse(cond_str) do
      {:ok, condition, _} ->
        {body_lines, remaining} = take_until(rest, ["elseif", "else", "endif"])

        case parse(body_lines) do
          {:ok, body} ->
            {further_blocks, remaining} = parse_elseif_blocks(remaining)
            {[%AST.ElseIf{condition: condition, block: body} | further_blocks], remaining}

          _ ->
            {[], ["elseif " <> cond_str | rest]}
        end

      _ ->
        {[], ["elseif " <> cond_str | rest]}
    end
  end

  defp parse_elseif_blocks(rest), do: {[], rest}

  defp handle_while(cond_str, rest) do
    cond_str = strip_parens(cond_str)

    case Expression.parse(cond_str) do
      {:ok, condition, _} ->
        {body_lines, remaining} = take_until(rest, ["endwhile"])

        case {parse(body_lines), remaining} do
          {{:ok, body}, ["endwhile" | rest]} ->
            {:ok, %AST.While{condition: condition, body: body}, rest}

          _ ->
            {:error, :expected_endwhile}
        end

      err ->
        err
    end
  end

  defp handle_for(for_str, rest) do
    # Try: for var in (expr)
    case Regex.run(~r/(\w+)\s+in\s+\((.+)\)/, for_str) do
      [_, var, expr_str] ->
        case Expression.parse(expr_str) do
          {:ok, list_expr, _} -> parse_for_body(var, list_expr, rest)
          err -> err
        end

      _ ->
        # Try: for var in [expr1..expr2]
        case Regex.run(~r/(\w+)\s+in\s+\[(.+)\.\.(.+)\]/, for_str) do
          [_, var, start_str, end_str] ->
            parse_for_range(var, start_str, end_str, rest)

          _ ->
            {:error, {:invalid_for, for_str}}
        end
    end
  end

  defp parse_for_body(var, list_expr, rest) do
    {body_lines, remaining} = take_until(rest, ["endfor"])

    case {parse(body_lines), remaining} do
      {{:ok, body}, ["endfor" | rest]} ->
        {:ok, %AST.ForList{var: var, list: list_expr, body: body}, rest}

      _ ->
        {:error, :expected_endfor}
    end
  end

  defp parse_for_range(var, start_str, end_str, rest) do
    with {:ok, start_expr, _} <- Expression.parse(start_str),
         {:ok, end_expr, _} <- Expression.parse(end_str) do
      {body_lines, remaining} = take_until(rest, ["endfor"])

      case {parse(body_lines), remaining} do
        {{:ok, body}, ["endfor" | rest]} ->
          range_node = %AST.Range{expr: nil, start: start_expr, end: end_expr}
          {:ok, %AST.For{var: var, range: range_node, body: body}, rest}

        _ ->
          {:error, :expected_endfor}
      end
    end
  end

  defp handle_return(rest_str, rest) do
    rest_str = String.trim(rest_str) |> String.trim_trailing(";")

    case rest_str do
      "" ->
        {:ok, %AST.Return{value: %AST.Literal{value: Value.num(0)}}, rest}

      _ ->
        case Expression.parse(rest_str) do
          {:ok, val_expr, _} -> {:ok, %AST.Return{value: val_expr}, rest}
          err -> err
        end
    end
  end

  defp handle_try(rest) do
    {body_lines, remaining} = take_until(rest, ["except", "finally", "endtry"])

    case parse(body_lines) do
      {:ok, body} ->
        parse_try_rest(body, remaining)

      err ->
        err
    end
  end

  defp parse_try_rest(body, ["except " <> except_str | rest]) do
    {var, codes_str} = split_except_header(String.trim(except_str))
    codes = parse_except_codes(codes_str)

    {except_lines, remaining} = take_until(rest, ["except", "finally", "endtry"])

    case {parse(except_lines), remaining} do
      {{:ok, except_body}, _} ->
        clause = %AST.Except{error_var: var, codes: codes, body: except_body}
        parse_try_rest_clauses(body, remaining, [clause])

      err ->
        err
    end
  end

  defp parse_try_rest(body, ["finally" | rest]) do
    {finally_lines, remaining} = take_until(rest, ["endtry"])

    case {parse(finally_lines), remaining} do
      {{:ok, finally_body}, ["endtry" | rest]} ->
        {:ok, %AST.Try{body: body, except_clauses: [], finally_block: finally_body}, rest}

      _ ->
        {:error, :expected_endtry}
    end
  end

  defp parse_try_rest(body, ["endtry" | rest]) do
    {:ok, %AST.Try{body: body, except_clauses: [], finally_block: nil}, rest}
  end

  defp parse_try_rest(_, _), do: {:error, :expected_endtry}

  defp split_except_header(str) do
    str = String.trim(str)

    cond do
      str == "ANY" ->
        {nil, "ANY"}

      String.starts_with?(str, "(") ->
        # No variable, just codes
        {nil, str}

      true ->
        # Possibly: var (CODES) or just var
        case String.split(str, ~r/\s+/, parts: 2) do
          [var, codes] -> {var, codes}
          [var] -> {var, "ANY"}
        end
    end
  end

  defp parse_except_codes("ANY"), do: :ANY

  defp parse_except_codes("(" <> _ = parenthesized) do
    inner = strip_parens(parenthesized)

    case Expression.parse(inner) do
      {:ok, expr, _} -> expr
      _ -> :ANY
    end
  end

  defp parse_except_codes(_), do: :ANY

  defp parse_try_rest_clauses(body, ["except " <> except_str | rest], acc) do
    # Parse another except clause
    case parse_try_rest(body, ["except " <> except_str | rest]) do
      {:ok, %AST.Try{except_clauses: new_clauses}, remaining} ->
        {:ok, %AST.Try{body: body, except_clauses: acc ++ new_clauses, finally_block: nil},
         remaining}

      err ->
        err
    end
  end

  defp parse_try_rest_clauses(body, ["finally" | rest], acc) do
    {finally_lines, remaining} = take_until(rest, ["endtry"])

    case {parse(finally_lines), remaining} do
      {{:ok, finally_body}, ["endtry" | rest]} ->
        {:ok,
         %AST.Try{
           body: body,
           except_clauses: acc,
           finally_block: finally_body
         }, rest}

      _ ->
        {:error, :expected_endtry}
    end
  end

  defp parse_try_rest_clauses(body, ["endtry" | rest], acc) do
    {:ok, %AST.Try{body: body, except_clauses: acc, finally_block: nil}, rest}
  end

  defp parse_try_rest_clauses(_, _, _), do: {:error, :expected_endtry}

  defp strip_parens(str) do
    str = String.trim(str)

    case {String.starts_with?(str, "("), String.ends_with?(str, ")")} do
      {true, true} ->
        # Only remove one from each end
        String.slice(str, 1, String.length(str) - 2)

      _ ->
        str
    end
  end

  defp parse_if_rest(condition, then_block, elseifs, ["endif" | rest]) do
    {:ok,
     %AST.If{
       condition: condition,
       then_block: then_block,
       elseif_blocks: elseifs,
       else_block: nil
     }, rest}
  end

  defp parse_if_rest(condition, then_block, elseifs, ["else" | rest]) do
    {else_lines, remaining} = take_until(rest, ["endif"])

    case {parse(else_lines), remaining} do
      {{:ok, else_block}, ["endif" | rest]} ->
        {:ok,
         %AST.If{
           condition: condition,
           then_block: then_block,
           elseif_blocks: elseifs,
           else_block: else_block
         }, rest}

      _ ->
        {:error, :expected_endif}
    end
  end

  defp parse_if_rest(condition, then_block, elseifs, rest) do
    {:ok,
     %AST.If{
       condition: condition,
       then_block: then_block,
       elseif_blocks: elseifs,
       else_block: nil
     }, rest}
  end

  defp take_until(lines, keywords) do
    take_until(lines, keywords, 0, [])
  end

  defp take_until([], _keywords, _depth, acc), do: {Enum.reverse(acc), []}

  defp take_until([line | rest], stop_keywords, depth, acc) do
    is_opener = block_opener?(line)
    is_closer = block_closer?(line)
    is_stop = Enum.any?(stop_keywords, &String.starts_with?(line, &1))

    cond do
      depth == 0 and is_stop ->
        {Enum.reverse(acc), [line | rest]}

      is_opener ->
        take_until(rest, stop_keywords, depth + 1, [line | acc])

      is_closer ->
        take_until(rest, stop_keywords, max(0, depth - 1), [line | acc])

      true ->
        take_until(rest, stop_keywords, depth, [line | acc])
    end
  end

  defp block_opener?(line) do
    line == "try" or
      String.starts_with?(line, "if ") or
      String.starts_with?(line, "while ") or
      String.starts_with?(line, "for ")
  end

  defp block_closer?(line) do
    line == "endif" or line == "endwhile" or line == "endfor" or line == "endtry"
  end
end
