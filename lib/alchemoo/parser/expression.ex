defmodule Alchemoo.Parser.Expression do
  @moduledoc """
  Simple recursive descent parser for MOO expressions.

  This is a minimal parser to get started. A full MOO parser would
  use a proper parser generator or more sophisticated techniques.
  """

  alias Alchemoo.AST
  alias Alchemoo.Value

  @doc """
  Parse a MOO expression from a string.

  ## Examples

      iex> parse("42")
      {:ok, %AST.Literal{value: {:num, 42}}}
      
      iex> parse("1 + 2")
      {:ok, %AST.BinOp{op: :+, left: %AST.Literal{...}, right: %AST.Literal{...}}}
  """
  def parse(input) when is_binary(input) do
    tokens = tokenize(input)
    parse_expr(tokens)
  end

  # Tokenize input into list of tokens
  defp tokenize(input) do
    # Simple tokenizer - handle negative numbers specially
    input
    |> String.trim()
    # Protect negative numbers from being split
    |> String.replace(~r/(\s|^)-(\d)/, "\\1NEG\\2")
    |> String.replace(~r/([\+\*\/\(\)\{\},;])/, " \\1 ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.replace(&1, "NEG", "-"))
  end

  # Parse expression (handles operators with precedence)
  defp parse_expr(tokens) do
    parse_comparison(tokens)
  end

  # Comparison operators: ==, !=, <, >, <=, >=
  defp parse_comparison(tokens) do
    with {:ok, left, rest} <- parse_additive(tokens) do
      case rest do
        ["==" | rest] ->
          {:ok, right, rest} = parse_additive(rest)
          {:ok, %AST.BinOp{op: :==, left: left, right: right}, rest}

        ["!=" | rest] ->
          {:ok, right, rest} = parse_additive(rest)
          {:ok, %AST.BinOp{op: :!=, left: left, right: right}, rest}

        _ ->
          {:ok, left, rest}
      end
    end
  end

  # Additive operators: +, -
  defp parse_additive(tokens) do
    with {:ok, left, rest} <- parse_multiplicative(tokens) do
      parse_additive_rest(left, rest)
    end
  end

  defp parse_additive_rest(left, ["+" | rest]) do
    {:ok, right, rest} = parse_multiplicative(rest)
    node = %AST.BinOp{op: :+, left: left, right: right}
    parse_additive_rest(node, rest)
  end

  defp parse_additive_rest(left, ["-" | rest]) do
    {:ok, right, rest} = parse_multiplicative(rest)
    node = %AST.BinOp{op: :-, left: left, right: right}
    parse_additive_rest(node, rest)
  end

  defp parse_additive_rest(left, rest), do: {:ok, left, rest}

  # Multiplicative operators: *, /, %
  defp parse_multiplicative(tokens) do
    with {:ok, left, rest} <- parse_primary(tokens) do
      parse_multiplicative_rest(left, rest)
    end
  end

  defp parse_multiplicative_rest(left, ["*" | rest]) do
    {:ok, right, rest} = parse_primary(rest)
    node = %AST.BinOp{op: :*, left: left, right: right}
    parse_multiplicative_rest(node, rest)
  end

  defp parse_multiplicative_rest(left, ["/" | rest]) do
    {:ok, right, rest} = parse_primary(rest)
    node = %AST.BinOp{op: :/, left: left, right: right}
    parse_multiplicative_rest(node, rest)
  end

  defp parse_multiplicative_rest(left, rest), do: {:ok, left, rest}

  # Primary expressions: literals, variables, parentheses
  defp parse_primary([<<"\"", _::binary>> = token | rest]) do
    str = token |> String.trim("\"") |> unescape_string()
    {:ok, %AST.Literal{value: Value.str(str)}, rest}
  end

  defp parse_primary([<<"#", rest_token::binary>> | rest]) do
    num = String.to_integer(rest_token)
    {:ok, %AST.Literal{value: Value.obj(num)}, rest}
  end

  defp parse_primary(["(" | rest]) do
    {:ok, expr, [")" | rest]} = parse_expr(rest)
    {:ok, expr, rest}
  end

  defp parse_primary(["{" | rest]) do
    parse_list(rest)
  end

  defp parse_primary([token | rest]) do
    cond do
      Regex.match?(~r/^-?\d+$/, token) ->
        {:ok, %AST.Literal{value: Value.num(String.to_integer(token))}, rest}

      Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, token) ->
        case rest do
          ["(" | args_tokens] ->
            # Function call
            {:ok, args, rest} = parse_func_args(args_tokens, [])
            {:ok, %AST.FuncCall{name: token, args: args}, rest}

          _ ->
            # Variable
            {:ok, %AST.Var{name: token}, rest}
        end

      true ->
        {:error, {:unexpected_token, token}}
    end
  end

  defp parse_primary([]) do
    {:error, :unexpected_end}
  end

  # Parse function arguments: expr, expr, ... )
  defp parse_func_args([")" | rest], acc), do: {:ok, Enum.reverse(acc), rest}

  defp parse_func_args(tokens, acc) do
    {:ok, expr, rest} = parse_expr(tokens)

    case rest do
      ["," | rest] -> parse_func_args(rest, [expr | acc])
      [")" | _] -> parse_func_args(rest, [expr | acc])
      _ -> {:error, :expected_comma_or_paren}
    end
  end

  # Parse list literal: {1, 2, 3}
  defp parse_list(tokens) do
    parse_list_elements(tokens, [])
  end

  defp parse_list_elements(["}" | rest], acc) do
    {:ok, %AST.ListExpr{elements: Enum.reverse(acc)}, rest}
  end

  defp parse_list_elements(tokens, acc) do
    {:ok, elem, rest} = parse_expr(tokens)

    case rest do
      ["," | rest] -> parse_list_elements(rest, [elem | acc])
      ["}" | _] = rest -> parse_list_elements(rest, [elem | acc])
      _ -> {:error, :expected_comma_or_brace}
    end
  end

  # Unescape string literals
  defp unescape_string(str) do
    str
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\"", "\"")
    |> String.replace("\\\\", "\\")
  end
end
