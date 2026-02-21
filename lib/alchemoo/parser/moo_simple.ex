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
    lines
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "//") or String.starts_with?(&1, "#")))
    |> parse_statements([])
  end

  def parse(code) when is_binary(code) do
    code
    |> String.split("\n")
    |> parse()
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
    # Parse if statement - remove parentheses if present
    cond_str =
      cond_str
      |> String.trim()
      |> String.trim_leading("(")
      |> String.trim_trailing(")")

    {:ok, condition, _} = Expression.parse(cond_str)

    {then_lines, rest} = take_until(rest, ["elseif", "else", "endif"])
    {:ok, then_block} = parse(then_lines)

    case rest do
      ["endif" | rest] ->
        {:ok,
         %AST.If{
           condition: condition,
           then_block: then_block,
           elseif_blocks: [],
           else_block: nil
         }, rest}

      ["else" | rest] ->
        {else_lines, ["endif" | rest]} = take_until(rest, ["endif"])
        {:ok, else_block} = parse(else_lines)

        {:ok,
         %AST.If{
           condition: condition,
           then_block: then_block,
           elseif_blocks: [],
           else_block: else_block
         }, rest}

      _ ->
        {:ok,
         %AST.If{
           condition: condition,
           then_block: then_block,
           elseif_blocks: [],
           else_block: nil
         }, rest}
    end
  end

  defp parse_statement("while " <> cond_str, rest) do
    cond_str =
      cond_str
      |> String.trim()
      |> String.trim_leading("(")
      |> String.trim_trailing(")")

    {:ok, condition, _} = Expression.parse(cond_str)

    {body_lines, ["endwhile" | rest]} = take_until(rest, ["endwhile"])
    {:ok, body} = parse(body_lines)

    {:ok, %AST.While{condition: condition, body: body}, rest}
  end

  defp parse_statement("for " <> for_str, rest) do
    # Parse: for var in (expr)
    case Regex.run(~r/(\w+)\s+in\s+\((.+)\)/, for_str) do
      [_, var, expr_str] ->
        {:ok, list_expr, _} = Expression.parse(expr_str)

        {body_lines, ["endfor" | rest]} = take_until(rest, ["endfor"])
        {:ok, body} = parse(body_lines)

        {:ok, %AST.ForList{var: var, list: list_expr, body: body}, rest}

      _ ->
        {:error, {:invalid_for, for_str}}
    end
  end

  defp parse_statement("return" <> rest_str, rest) do
    rest_str = String.trim(rest_str) |> String.trim_trailing(";")

    case rest_str do
      "" ->
        {:ok, %AST.Return{value: %AST.Literal{value: Value.num(0)}}, rest}

      _ ->
        {:ok, val_expr, _} = Expression.parse(rest_str)
        {:ok, %AST.Return{value: val_expr}, rest}
    end
  end

  defp parse_statement("break" <> _, rest) do
    {:ok, %AST.Break{}, rest}
  end

  defp parse_statement("continue" <> _, rest) do
    {:ok, %AST.Continue{}, rest}
  end

  defp parse_statement(line, rest) do
    line = String.trim_trailing(line, ";")

    # Check for assignment
    case String.contains?(line, "=") and not String.contains?(line, "==") and
           not String.contains?(line, "!=") do
      true ->
        [target_str, value_str] = String.split(line, "=", parts: 2)
        target_str = String.trim(target_str)
        value_str = String.trim(value_str)

        {:ok, value_expr, _} = Expression.parse(value_str)

        target =
          case String.match?(target_str, ~r/^\w+$/) do
            true ->
              %AST.Var{name: target_str}

            false ->
              # Property assignment or complex target
              {:ok, target_ast, _} = Expression.parse(target_str)
              target_ast
          end

        {:ok, %AST.Assignment{target: target, value: value_expr}, rest}

      false ->
        # Expression statement
        {:ok, expr, _} = Expression.parse(line)
        {:ok, %AST.ExprStmt{expr: expr}, rest}
    end
  end

  defp take_until(lines, keywords) do
    take_until(lines, keywords, [])
  end

  defp take_until([line | rest] = all, keywords, acc) do
    case Enum.any?(keywords, &String.starts_with?(line, &1)) do
      true -> {Enum.reverse(acc), all}
      false -> take_until(rest, keywords, [line | acc])
    end
  end

  defp take_until([], _keywords, acc) do
    {Enum.reverse(acc), []}
  end
end
