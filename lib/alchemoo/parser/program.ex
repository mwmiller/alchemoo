defmodule Alchemoo.Parser.Program do
  @moduledoc """
  Recursive MOO program parser.
  Handles nested blocks by strictly managing expected terminators.
  """

  alias Alchemoo.AST
  alias Alchemoo.Parser.Expression
  alias Alchemoo.Value

  @closers ["endif", "endwhile", "endfor", "endtry"]
  @mid_terminators ["else", "elseif", "except", "finally"]

  @doc """
  Parse MOO code into an AST block.
  Returns {:ok, %AST.Block{}} or {:error, reason}.
  """
  def parse(code) when is_list(code) do
    case parse_until(code, []) do
      {:ok, block, []} -> {:ok, block}
      {:ok, block, ["." | _]} -> {:ok, block}
      {:ok, _block, [extra | _]} -> {:error, {:unexpected_token, extra}}
      err -> err
    end
  end

  def parse(code) when is_binary(code) do
    code
    |> String.split("\n")
    |> parse()
  end

  defp parse_until(lines, terminators) do
    case do_parse(lines, terminators, []) do
      {:ok, statements, remaining} ->
        {:ok, %AST.Block{statements: statements}, remaining}
      err -> err
    end
  end

  defp do_parse([], terminators, acc) do
    if terminators == [] do
      {:ok, Enum.reverse(acc), []}
    else
      {:error, {:missing_closer, hd(terminators)}}
    end
  end

  defp do_parse([line | rest] = all, terminators, acc) do
    trimmed = 
      line 
      |> String.split("#", parts: 2) 
      |> hd() 
      |> String.trim()

    cond do
      trimmed == "" or String.starts_with?(trimmed, "\"") ->
        do_parse(rest, terminators, acc)

      trimmed == "." ->
        {:ok, Enum.reverse(acc), ["."]}

      is_specific_terminator?(trimmed, terminators) ->
        {:ok, Enum.reverse(acc), all}

      Enum.member?(@closers, trimmed) or Enum.member?(@mid_terminators, trimmed) ->
        {:error, {:unexpected_closer, trimmed}}

      true ->
        case parse_statement(trimmed, rest) do
          {:ok, stmt, remaining} ->
            do_parse(remaining, terminators, [stmt | acc])
          err -> err
        end
    end
  end

  defp is_specific_terminator?(line, terminators) do
    Enum.member?(terminators, line) or 
    Enum.any?(terminators, &String.starts_with?(line, &1))
  end

  defp parse_statement(line, rest) do
    cond do
      starts_with_keyword?(line, "if") ->
        handle_if(strip_keyword(line, "if"), rest)

      starts_with_keyword?(line, "while") ->
        handle_while(strip_keyword(line, "while"), rest)

      starts_with_keyword?(line, "for") ->
        handle_for(strip_keyword(line, "for"), rest)

      starts_with_keyword?(line, "return") ->
        handle_return(strip_keyword(line, "return"), rest)

      line == "break" or String.starts_with?(line, "break;") ->
        {:ok, %AST.Break{}, rest}

      line == "continue" or String.starts_with?(line, "continue ") or String.starts_with?(line, "continue;") ->
        {:ok, %AST.Continue{}, rest}

      line == "try" ->
        handle_try(rest)

      true ->
        expr_line = String.trim_trailing(line, ";")
        case Expression.parse(expr_line) do
          {:ok, expr, _} -> {:ok, %AST.ExprStmt{expr: expr}, rest}
          err -> err
        end
    end
  end

  defp starts_with_keyword?(line, kw) do
    String.starts_with?(line, kw) and 
    (String.length(line) == String.length(kw) or 
     String.at(line, String.length(kw)) in [" ", "("])
  end

  defp strip_keyword(line, kw) do
    line |> String.slice(String.length(kw)..-1//1) |> String.trim()
  end

  defp handle_if(cond_str, rest) do
    case Expression.parse(cond_str) do
      {:ok, condition, _} ->
        case parse_until(rest, ["elseif", "else", "endif"]) do
          {:ok, then_block, remaining} ->
            parse_if_rest(condition, then_block, [], remaining)
          err -> err
        end
      err -> err
    end
  end

  defp parse_if_rest(condition, then_block, elseifs, [line | rest]) do
    trimmed = line |> String.split("#", parts: 2) |> hd() |> String.trim()
    
    cond do
      String.starts_with?(trimmed, "elseif") ->
        next_cond_str = strip_keyword(trimmed, "elseif")
        case Expression.parse(next_cond_str) do
          {:ok, next_cond, _} ->
            case parse_until(rest, ["elseif", "else", "endif"]) do
              {:ok, elseif_body, remaining} ->
                elseif_node = %AST.ElseIf{condition: next_cond, block: elseif_body}
                parse_if_rest(condition, then_block, elseifs ++ [elseif_node], remaining)
              err -> err
            end
          err -> err
        end

      trimmed == "else" ->
        case parse_until(rest, ["endif"]) do
          {:ok, else_block, [endif_line | final_rest]} ->
            trimmed_endif = endif_line |> String.split("#", parts: 2) |> hd() |> String.trim()
            if trimmed_endif == "endif" do
              {:ok, %AST.If{condition: condition, then_block: then_block, elseif_blocks: elseifs, else_block: else_block}, final_rest}
            else
              {:error, {:expected_endif, endif_line}}
            end
          err -> err
        end

      trimmed == "endif" ->
        {:ok, %AST.If{condition: condition, then_block: then_block, elseif_blocks: elseifs, else_block: nil}, rest}

      true -> {:error, {:expected_endif, line}}
    end
  end
  defp parse_if_rest(_, _, _, []), do: {:error, :expected_endif}

  defp handle_while(cond_str, rest) do
    case Expression.parse(cond_str) do
      {:ok, condition, _} ->
        case parse_until(rest, ["endwhile"]) do
          {:ok, body, [closer | remaining]} ->
            trimmed_closer = closer |> String.split("#", parts: 2) |> hd() |> String.trim()
            if trimmed_closer == "endwhile" do
              {:ok, %AST.While{condition: condition, body: body}, remaining}
            else
              {:error, :expected_endwhile}
            end
          err -> err
        end
      err -> err
    end
  end

  defp handle_for(for_str, rest) do
    case Regex.run(~r/(\w+)\s+in\s+\[(.+)\.\.(.+)\]/, for_str) do
      [_, var, start_s, end_s] ->
        with {:ok, start_e, _} <- Expression.parse(start_s),
             {:ok, end_e, _} <- Expression.parse(end_s) do
          case parse_until(rest, ["endfor"]) do
            {:ok, body, [closer | remaining]} ->
              trimmed_closer = closer |> String.split("#", parts: 2) |> hd() |> String.trim()
              if trimmed_closer == "endfor" do
                range = %AST.Range{start: start_e, end: end_e}
                {:ok, %AST.For{var: var, range: range, body: body}, remaining}
              else
                {:error, :expected_endfor}
              end
            err -> err
          end
        end
      _ ->
        case Regex.run(~r/(\w+)\s+in\s+(.+)/, for_str) do
          [_, var, list_s] ->
            case Expression.parse(list_s) do
              {:ok, list_e, _} ->
                case parse_until(rest, ["endfor"]) do
                  {:ok, body, [closer | remaining]} ->
                    trimmed_closer = closer |> String.split("#", parts: 2) |> hd() |> String.trim()
                    if trimmed_closer == "endfor" do
                      {:ok, %AST.ForList{var: var, list: list_e, body: body}, remaining}
                    else
                      {:error, :expected_endfor}
                    end
                  err -> err
                end
              err -> err
            end
          _ -> {:error, {:invalid_for, for_str}}
        end
    end
  end

  defp strip_outer_parens(s) do
    s = String.trim(s)
    if String.starts_with?(s, "(") and String.ends_with?(s, ")") do
      String.slice(s, 1..-2//1)
    else
      s
    end
  end

  defp handle_return(rest_str, rest) do
    case String.trim_trailing(String.trim(rest_str), ";") do
      "" -> {:ok, %AST.Return{value: %AST.Literal{value: Value.num(0)}}, rest}
      val_s ->
        case Expression.parse(val_s) do
          {:ok, val_e, _} -> {:ok, %AST.Return{value: val_e}, rest}
          err -> err
        end
    end
  end

  defp handle_try(rest) do
    case parse_until(rest, ["except", "finally", "endtry"]) do
      {:ok, body, remaining} -> parse_try_rest(body, remaining)
      err -> err
    end
  end

  defp parse_try_rest(body, [line | rest]) do
    trimmed = line |> String.split("#", parts: 2) |> hd() |> String.trim()
    cond do
      String.starts_with?(trimmed, "except") ->
        "except" <> except_s = trimmed
        {var, codes_s} = split_except_header(String.trim(except_s))
        codes = parse_except_codes(codes_s)
        case parse_until(rest, ["except", "finally", "endtry"]) do
          {:ok, except_body, remaining} ->
            clause = %AST.Except{error_var: var, codes: codes, body: except_body}
            parse_try_rest_clauses(body, remaining, [clause])
          err -> err
        end
      trimmed == "finally" ->
        case parse_until(rest, ["endtry"]) do
          {:ok, finally_body, [closer | remaining]} ->
            trimmed_closer = closer |> String.split("#", parts: 2) |> hd() |> String.trim()
            if trimmed_closer == "endtry" do
              {:ok, %AST.Try{body: body, except_clauses: [], finally_block: finally_body}, remaining}
            else
              {:error, :expected_endtry}
            end
          err -> err
        end
      trimmed == "endtry" ->
        {:ok, %AST.Try{body: body, except_clauses: [], finally_block: nil}, rest}
      true -> {:error, {:expected_endtry, line}}
    end
  end
  defp parse_try_rest(_, []), do: {:error, :expected_endtry}

  defp parse_try_rest_clauses(body, [line | rest], acc) do
    trimmed = line |> String.split("#", parts: 2) |> hd() |> String.trim()
    cond do
      String.starts_with?(trimmed, "except") ->
        "except" <> except_s = trimmed
        {var, codes_s} = split_except_header(String.trim(except_s))
        codes = parse_except_codes(codes_s)
        case parse_until(rest, ["except", "finally", "endtry"]) do
          {:ok, except_body, remaining} ->
            clause = %AST.Except{error_var: var, codes: codes, body: except_body}
            parse_try_rest_clauses(body, remaining, [clause | acc])
          err -> err
        end
      trimmed == "finally" ->
        case parse_until(rest, ["endtry"]) do
          {:ok, finally_body, [closer | remaining]} ->
            trimmed_closer = closer |> String.split("#", parts: 2) |> hd() |> String.trim()
            if trimmed_closer == "endtry" do
              {:ok, %AST.Try{body: body, except_clauses: Enum.reverse(acc), finally_block: finally_body}, remaining}
            else
              {:error, :expected_endtry}
            end
          err -> err
        end
      trimmed == "endtry" ->
        {:ok, %AST.Try{body: body, except_clauses: Enum.reverse(acc), finally_block: nil}, rest}
      true -> {:error, {:expected_endtry, line}}
    end
  end
  defp parse_try_rest_clauses(_, []), do: {:error, :expected_endtry}

  defp split_except_header(str) do
    case String.split(str, ~r/\s+/, parts: 2) do
      [var, codes] ->
        if String.starts_with?(var, "(") do {nil, str} else {var, codes} end
      [one] ->
        if String.starts_with?(one, "(") or one == "ANY" do {nil, one} else {one, "ANY"} end
    end
  end

  defp parse_except_codes("ANY"), do: :ANY
  defp parse_except_codes(s) do
    case Expression.parse(strip_outer_parens(s)) do
      {:ok, :ANY, _} -> :ANY
      {:ok, %AST.Literal{value: {:err, :ANY}}, _} -> :ANY
      {:ok, expr, _} -> expr
      _ -> :ANY
    end
  end
end
