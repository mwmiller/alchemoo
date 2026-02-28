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
    # Regex to match:
    # 1. String literals: "([^"\\]|\\.)*"
    # 2. Object IDs: #[0-9]+
    # 3. Identifiers and numbers: [a-zA-Z_][a-zA-Z0-9_]* | -?[0-9]+
    # 4. Multi-char operators: == | != | <= | >= | && | || | ..
    # 5. Single-char symbols: [\(\)\{\}\[\]\+\-\*\/\%\,\;\:\.\?\|\=\<\>\!\&\@\.]
    token_regex =
      ~r/"(?:[^"\\]|\\.)*"|#-?[0-9]+|-?(?:\d+\.(?!\.)\d*|\.\d+)(?:[eE][+-]?\d+)?|-?\d+[eE][+-]?\d+|-?[0-9]+|[a-zA-Z_][a-zA-Z0-9_]*|==|!=|<=|>=|&&|\|\||\.\.|=>|\$|[\(\)\{\}\[\]\+\-\*\/\%\^\,\;\:\.\?\|\=\<\>\!\&\@\`\']/

    Regex.scan(token_regex, input)
    |> Enum.map(fn [match] -> match end)
  end

  # Parse expression (handles operators with precedence)
  defp parse_expr(tokens) do
    parse_assignment(tokens)
  end

  # Assignment: var = expr
  defp parse_assignment(tokens) do
    with {:ok, left, ["=" | rest]} <- parse_conditional(tokens) do
      handle_assignment_rest(left, rest)
    end
  end

  defp handle_assignment_rest(left, rest) do
    case valid_assignment_target?(left) do
      true ->
        with {:ok, right, rest} <- parse_assignment(rest) do
          {:ok, %AST.Assignment{target: left, value: right}, rest}
        end

      false ->
        {:error, :invalid_assignment_target}
    end
  end

  defp valid_assignment_target?(%AST.Var{}), do: true
  defp valid_assignment_target?(%AST.PropRef{}), do: true
  defp valid_assignment_target?(%AST.Index{}), do: true
  defp valid_assignment_target?(%AST.Range{}), do: true
  defp valid_assignment_target?(%AST.ListExpr{}), do: true
  defp valid_assignment_target?(_), do: false

  # Conditional expression: cond ? then | else
  defp parse_conditional(tokens) do
    case parse_logical_or(tokens) do
      {:ok, left, ["?" | rest]} ->
        handle_conditional_rest(left, rest)

      other ->
        other
    end
  end

  defp handle_conditional_rest(left, rest) do
    case parse_expr(rest) do
      {:ok, then_expr, ["|" | rest]} ->
        case parse_expr(rest) do
          {:ok, else_expr, rest} ->
            {:ok, %AST.Conditional{condition: left, then_expr: then_expr, else_expr: else_expr},
             rest}

          _ ->
            {:error, :invalid_conditional}
        end

      _ ->
        {:error, :invalid_conditional}
    end
  end

  # Logical OR: ||
  defp parse_logical_or(tokens) do
    with {:ok, left, rest} <- parse_logical_and(tokens) do
      parse_logical_or_rest(left, rest)
    end
  end

  defp parse_logical_or_rest(left, ["||" | rest]) do
    with {:ok, right, rest} <- parse_logical_and(rest) do
      node = %AST.BinOp{op: :||, left: left, right: right}
      parse_logical_or_rest(node, rest)
    end
  end

  defp parse_logical_or_rest(left, rest), do: {:ok, left, rest}

  # Logical AND: &&
  defp parse_logical_and(tokens) do
    with {:ok, left, rest} <- parse_comparison(tokens) do
      parse_logical_and_rest(left, rest)
    end
  end

  defp parse_logical_and_rest(left, ["&&" | rest]) do
    with {:ok, right, rest} <- parse_comparison(rest) do
      node = %AST.BinOp{op: :&&, left: left, right: right}
      parse_logical_and_rest(node, rest)
    end
  end

  defp parse_logical_and_rest(left, rest), do: {:ok, left, rest}

  # Comparison operators: ==, !=, <, >, <=, >=, in
  defp parse_comparison(tokens) do
    case parse_additive(tokens) do
      {:ok, left, [op | rest]} when op in ["==", "!=", "<", ">", "<=", ">=", "in"] ->
        case parse_additive(rest) do
          {:ok, right, rest} ->
            {:ok, %AST.BinOp{op: String.to_atom(op), left: left, right: right}, rest}

          err ->
            err
        end

      other ->
        other
    end
  end

  # Additive operators: +, -
  defp parse_additive(tokens) do
    with {:ok, left, rest} <- parse_multiplicative(tokens) do
      parse_additive_rest(left, rest)
    end
  end

  defp parse_additive_rest(left, ["+" | rest]) do
    with {:ok, right, rest} <- parse_multiplicative(rest) do
      node = %AST.BinOp{op: :+, left: left, right: right}
      parse_additive_rest(node, rest)
    end
  end

  defp parse_additive_rest(left, ["-" | rest]) do
    with {:ok, right, rest} <- parse_multiplicative(rest) do
      node = %AST.BinOp{op: :-, left: left, right: right}
      parse_additive_rest(node, rest)
    end
  end

  defp parse_additive_rest(left, rest), do: {:ok, left, rest}

  # Multiplicative operators: *, /, %
  defp parse_multiplicative(tokens) do
    with {:ok, left, rest} <- parse_unary(tokens) do
      parse_multiplicative_rest(left, rest)
    end
  end

  defp parse_multiplicative_rest(left, ["*" | rest]) do
    with {:ok, right, rest} <- parse_primary(rest) do
      node = %AST.BinOp{op: :*, left: left, right: right}
      parse_multiplicative_rest(node, rest)
    end
  end

  defp parse_multiplicative_rest(left, ["/" | rest]) do
    with {:ok, right, rest} <- parse_primary(rest) do
      node = %AST.BinOp{op: :/, left: left, right: right}
      parse_multiplicative_rest(node, rest)
    end
  end

  defp parse_multiplicative_rest(left, ["%" | rest]) do
    with {:ok, right, rest} <- parse_primary(rest) do
      node = %AST.BinOp{op: :%, left: left, right: right}
      parse_multiplicative_rest(node, rest)
    end
  end

  defp parse_multiplicative_rest(left, ["^" | rest]) do
    with {:ok, right, rest} <- parse_primary(rest) do
      node = %AST.BinOp{op: :^, left: left, right: right}
      parse_multiplicative_rest(node, rest)
    end
  end

  defp parse_multiplicative_rest(left, rest), do: {:ok, left, rest}

  # Unary operators: !, -
  defp parse_unary(["!" | rest]) do
    case parse_primary(rest) do
      {:ok, val, rest} -> {:ok, %AST.UnaryOp{op: :!, expr: val}, rest}
      err -> err
    end
  end

  defp parse_unary(["-" | rest]) do
    case parse_primary(rest) do
      {:ok, val, rest} -> {:ok, %AST.UnaryOp{op: :-, expr: val}, rest}
      err -> err
    end
  end

  defp parse_unary(tokens), do: parse_primary(tokens)

  # Primary expressions: literals, variables, parentheses, splice
  defp parse_primary(["@" | rest]) do
    # In LambdaMOO code, splices often apply to conditional expressions:
    #   @(cond ? {..} | {})
    # Parse a full conditional here, not just a primary term.
    with {:ok, expr, rest} <- parse_conditional(rest) do
      {:ok, %AST.UnaryOp{op: :@, expr: expr}, rest}
    end
  end

  defp parse_primary(["$" | rest]) do
    case rest do
      [name | rest] ->
        case Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name) do
          true -> handle_system_call_or_prop(name, rest)
          false -> parse_suffix(%AST.Var{name: "$"}, [name | rest])
        end

      [] ->
        parse_suffix(%AST.Var{name: "$"}, [])
    end
  end

  defp parse_primary(["`" | rest]) do
    case parse_expr(rest) do
      {:ok, expr, ["'" | rest]} ->
        # Just backticks without codes: `expr'
        parse_suffix(%AST.Catch{expr: expr, codes: nil, default: nil}, rest)

      {:ok, %AST.Catch{} = catch_node, ["'" | rest]} ->
        # With codes: `expr ! codes'
        parse_suffix(catch_node, rest)

      _ ->
        {:error, :expected_closing_quote}
    end
  end

  defp parse_primary([<<"\"", _::binary>> = token | rest]) do
    str = token |> String.trim("\"") |> unescape_string()
    parse_suffix(%AST.Literal{value: Value.str(str)}, rest)
  end

  defp parse_primary([<<"#", rest_token::binary>> | rest]) do
    case Integer.parse(rest_token) do
      {num, ""} -> parse_suffix(%AST.Literal{value: Value.obj(num)}, rest)
      _ -> {:error, {:invalid_object_id, rest_token}}
    end
  end

  defp parse_primary(["(" | rest]) do
    handle_paren_expr(rest)
  end

  defp parse_primary(["{" | rest]) do
    handle_list_expr(rest)
  end

  defp parse_primary([token | rest]) do
    cond do
      Regex.match?(~r/^-?(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?$/, token) ->
        with {:ok, val} <- parse_float_literal(token) do
          parse_suffix(%AST.Literal{value: {:float, val}}, rest)
        end

      Regex.match?(~r/^-?\d+[eE][+-]?\d+$/, token) ->
        with {:ok, val} <- parse_float_literal(token) do
          parse_suffix(%AST.Literal{value: {:float, val}}, rest)
        end

      Regex.match?(~r/^-?\d+$/, token) ->
        parse_suffix(%AST.Literal{value: Value.num(String.to_integer(token))}, rest)

      Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, token) ->
        handle_call_or_var(token, rest)

      true ->
        {:error, {:unexpected_token, token}}
    end
  end

  defp parse_primary([]) do
    {:error, :unexpected_end}
  end

  # --- Helper functions ---

  defp parse_catch_suffix(node, ["ANY" | rest]) do
    handle_catch_after_codes(node, :ANY, rest)
  end

  defp parse_catch_suffix(node, tokens) do
    case parse_expr(tokens) do
      {:ok, first_code, rest} ->
        case parse_more_catch_codes([first_code], rest) do
          {:ok, codes, rest} -> handle_catch_after_codes(node, codes, rest)
          err -> err
        end

      err ->
        err
    end
  end

  defp parse_more_catch_codes([single], ["," | rest]) do
    case parse_expr(rest) do
      {:ok, code, rest} -> parse_more_catch_codes([code, single], rest)
      err -> err
    end
  end

  defp parse_more_catch_codes(rev_codes, ["," | rest]) do
    case parse_expr(rest) do
      {:ok, code, rest} -> parse_more_catch_codes([code | rev_codes], rest)
      err -> err
    end
  end

  defp parse_more_catch_codes([single], rest), do: {:ok, single, rest}

  defp parse_more_catch_codes(rev_codes, rest),
    do: {:ok, %AST.ListExpr{elements: Enum.reverse(rev_codes)}, rest}

  defp handle_catch_after_codes(expr, codes, tokens) do
    case tokens do
      ["=>" | rest] ->
        case parse_expr(rest) do
          {:ok, default, rest} ->
            parse_suffix(%AST.Catch{expr: expr, codes: codes, default: default}, rest)

          err ->
            err
        end

      _ ->
        parse_suffix(%AST.Catch{expr: expr, codes: codes, default: nil}, tokens)
    end
  end

  defp handle_paren_expr(tokens) do
    case parse_expr(tokens) do
      {:ok, expr, [")" | rest]} ->
        parse_suffix(expr, rest)

      _ ->
        {:error, :expected_closing_paren}
    end
  end

  defp handle_list_expr(tokens) do
    case parse_list(tokens) do
      {:ok, list_node, rest} ->
        parse_suffix(list_node, rest)

      err ->
        err
    end
  end

  defp handle_call_or_var(name, ["(" | args_tokens]) do
    case parse_func_args(args_tokens, []) do
      {:ok, args, rest} ->
        parse_suffix(%AST.FuncCall{name: name, args: args}, rest)

      err ->
        err
    end
  end

  defp handle_call_or_var(name, rest) do
    parse_suffix(%AST.Var{name: name}, rest)
  end

  defp handle_system_call_or_prop(name, ["(" | args_tokens]) do
    case parse_func_args(args_tokens, []) do
      {:ok, args, rest} ->
        system_obj = %AST.Literal{value: Value.obj(0)}
        parse_suffix(%AST.VerbCall{obj: system_obj, verb: name, args: args}, rest)

      err ->
        err
    end
  end

  defp handle_system_call_or_prop(name, rest) do
    system_obj = %AST.Literal{value: Value.obj(0)}
    parse_suffix(%AST.PropRef{obj: system_obj, prop: name}, rest)
  end

  # Suffixes: .prop, :verb(), [idx], [start..end], !(codes => default)
  defp parse_suffix(node, ["!" | rest]) do
    # Catch expression: node ! codes [=> default]
    parse_catch_suffix(node, rest)
  end

  defp parse_suffix(node, [".", "(" | rest]) do
    with {:ok, prop_expr, [")" | rest]} <- parse_expr(rest) do
      parse_suffix(%AST.PropRef{obj: node, prop: prop_expr}, rest)
    end
  end

  defp parse_suffix(node, [".", prop_name | rest]) do
    parse_suffix(%AST.PropRef{obj: node, prop: prop_name}, rest)
  end

  defp parse_suffix(node, [":", "(" | rest]) do
    with {:ok, verb_expr, [")", "(" | rest]} <- parse_expr(rest),
         {:ok, args, rest} <- parse_func_args(rest, []) do
      parse_suffix(%AST.VerbCall{obj: node, verb: verb_expr, args: args}, rest)
    end
  end

  defp parse_suffix(node, [":", verb_name, "(" | rest]) do
    case parse_func_args(rest, []) do
      {:ok, args, rest} ->
        parse_suffix(%AST.VerbCall{obj: node, verb: verb_name, args: args}, rest)

      err ->
        err
    end
  end

  defp parse_suffix(node, ["[" | rest]) do
    case parse_expr(rest) do
      {:ok, start_expr, [".." | rest]} ->
        case parse_expr(rest) do
          {:ok, end_expr, ["]" | rest]} ->
            parse_suffix(%AST.Range{expr: node, start: start_expr, end: end_expr}, rest)

          _ ->
            {:error, :expected_closing_bracket}
        end

      {:ok, index_expr, ["]" | rest]} ->
        parse_suffix(%AST.Index{expr: node, index: index_expr}, rest)

      _ ->
        {:error, :expected_closing_bracket}
    end
  end

  defp parse_suffix(node, rest), do: {:ok, node, rest}

  # Parse function arguments: expr, expr, ... )
  defp parse_func_args([")" | rest], acc), do: {:ok, Enum.reverse(acc), rest}

  defp parse_func_args(tokens, acc) do
    case parse_expr(tokens) do
      {:ok, expr, rest} ->
        case rest do
          ["," | rest] -> parse_func_args(rest, [expr | acc])
          [")" | _] = rest -> parse_func_args(rest, [expr | acc])
          _ -> {:error, :expected_comma_or_paren}
        end

      err ->
        err
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
    case tokens do
      ["?" | rest] ->
        parse_optional_list_element(rest, acc)

      _ ->
        case parse_expr(tokens) do
          {:ok, elem, rest} ->
            handle_list_element_rest(elem, rest, acc)

          err ->
            err
        end
    end
  end

  defp parse_optional_list_element([name | rest], acc) do
    if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name) do
      handle_optional_var(name, rest, acc)
    else
      {:error, {:expected_variable_after_question, name}}
    end
  end

  defp parse_optional_list_element(_, _acc), do: {:error, :expected_variable_after_question}

  defp handle_optional_var(name, tokens, acc) do
    case tokens do
      ["=" | rest] ->
        case parse_expr(rest) do
          {:ok, default, rest} ->
            node = %AST.OptionalVar{name: name, default: default}
            handle_list_element_rest(node, rest, acc)

          err ->
            err
        end

      _ ->
        node = %AST.OptionalVar{name: name, default: nil}
        handle_list_element_rest(node, tokens, acc)
    end
  end

  defp handle_list_element_rest(elem, rest, acc) do
    case rest do
      ["," | rest] -> parse_list_elements(rest, [elem | acc])
      ["}" | _] = rest -> parse_list_elements(rest, [elem | acc])
      _ -> {:error, :expected_comma_or_brace}
    end
  end

  # Unescape string literals
  defp parse_float_literal(token) do
    case Float.parse(token) do
      {val, ""} -> {:ok, val}
      _ -> {:error, {:invalid_float, token}}
    end
  end

  defp unescape_string(str) do
    str
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\"", "\"")
    |> String.replace("\\\\", "\\")
  end
end
