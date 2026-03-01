defmodule Alchemoo.Parser.Expression do
  @moduledoc """
  Recursive descent parser for MOO expressions.
  Standard precedence climbing with robust tokenization.
  """

  alias Alchemoo.AST
  alias Alchemoo.Value

  @doc """
  Parse a MOO expression string into an AST node.
  """
  def parse(input) when is_binary(input) do
    case tokenize(input) do
      {:ok, tokens} -> parse_expr(tokens)
      err -> err
    end
  end

  def parse(tokens) when is_list(tokens) do
    parse_expr(tokens)
  end

  # --- Tokenizer ---

  defp tokenize(input), do: do_tokenize(String.trim(input), [])

  defp do_tokenize("", acc), do: {:ok, Enum.reverse(acc)}
  defp do_tokenize(input, acc) do
    input = String.trim_leading(input)
    if input == "" do
      do_tokenize("", acc)
    else
      case next_token(input) do
        {:ok, token, rest} -> do_tokenize(rest, [token | acc])
        err -> err
      end
    end
  end

  defp next_token(input) do
    cond do
      match = Regex.run(~r/^"(?:[^"\\]|\\.)*"/, input) ->
        [full] = match
        {:ok, full, skip(input, full)}

      match = Regex.run(~r/^(==|!=|<=|>=|&&|\|\||\.\.|=>)/, input) ->
        [full, _] = match
        {:ok, full, skip(input, full)}

      match = Regex.run(~r/^#-?\d+/, input) ->
        [full] = match
        {:ok, full, skip(input, full)}

      match = Regex.run(~r/^-?\d+\.\d*[eE][+-]?\d+/, input) ->
        [full] = match
        {:ok, full, skip(input, full)}
      
      match = Regex.run(~r/^-?\d+[eE][+-]?\d+/, input) ->
        [full] = match
        {:ok, full, skip(input, full)}

      match = Regex.run(~r/^-?\d+\.\d+(?!\.)/, input) ->
        [full] = match
        {:ok, full, skip(input, full)}

      match = Regex.run(~r/^-?\d+/, input) ->
        [full] = match
        {:ok, full, skip(input, full)}

      match = Regex.run(~r/^\$[a-zA-Z_][a-zA-Z0-9_]*/, input) ->
        [full] = match
        {:ok, full, skip(input, full)}
      
      match = Regex.run(~r/^[a-zA-Z_][a-zA-Z0-9_]*/, input) ->
        [full] = match
        {:ok, full, skip(input, full)}

      true ->
        char = String.at(input, 0)
        {:ok, char, String.slice(input, 1..-1//1)}
    end
  end

  defp skip(input, token), do: String.slice(input, String.length(token)..-1//1)

  # --- Recursive Descent ---

  defp parse_expr(tokens), do: parse_assignment(tokens)

  defp parse_assignment(tokens) do
    case parse_conditional(tokens) do
      {:ok, left, ["=" | rest]} ->
        case parse_assignment(rest) do
          {:ok, right, rem} -> {:ok, %AST.Assignment{target: left, value: right}, rem}
          err -> err
        end
      result -> result
    end
  end

  defp parse_conditional(tokens) do
    case parse_logical_or(tokens) do
      {:ok, condition, ["?" | rest]} ->
        case parse_expr(rest) do
          {:ok, then_e, ["|" | else_rest]} ->
            case parse_expr(else_rest) do
              {:ok, else_e, rem} -> {:ok, %AST.Conditional{condition: condition, then_expr: then_e, else_expr: else_e}, rem}
              err -> err
            end
          _ -> {:error, :expected_else_pipe}
        end
      result -> result
    end
  end

  defp parse_logical_or(tokens) do
    case parse_logical_and(tokens) do
      {:ok, left, ["||" | rest]} ->
        case parse_logical_or(rest) do
          {:ok, right, rem} -> {:ok, %AST.BinOp{op: :||, left: left, right: right}, rem}
          err -> err
        end
      result -> result
    end
  end

  defp parse_logical_and(tokens) do
    case parse_comparison(tokens) do
      {:ok, left, ["&&" | rest]} ->
        case parse_logical_and(rest) do
          {:ok, right, rem} -> {:ok, %AST.BinOp{op: :&&, left: left, right: right}, rem}
          err -> err
        end
      result -> result
    end
  end

  @comparison_ops ["==", "!=", "<", ">", "<=", ">=", "in"]
  defp parse_comparison(tokens) do
    case parse_additive(tokens) do
      {:ok, left, [op | rest]} when op in @comparison_ops ->
        case parse_additive(rest) do
          {:ok, right, rem} -> {:ok, %AST.BinOp{op: String.to_atom(op), left: left, right: right}, rem}
          err -> err
        end
      result -> result
    end
  end

  defp parse_additive(tokens) do
    case parse_multiplicative(tokens) do
      {:ok, left, [op | rest]} when op in ["+", "-"] ->
        case parse_multiplicative(rest) do
          {:ok, right, rem} -> {:ok, %AST.BinOp{op: String.to_atom(op), left: left, right: right}, rem}
          err -> err
        end
      result -> result
    end
  end

  defp parse_multiplicative(tokens) do
    case parse_power(tokens) do
      {:ok, left, [op | rest]} when op in ["*", "/", "%"] ->
        case parse_power(rest) do
          {:ok, right, rem} -> {:ok, %AST.BinOp{op: String.to_atom(op), left: left, right: right}, rem}
          err -> err
        end
      result -> result
    end
  end

  defp parse_power(tokens) do
    case parse_unary(tokens) do
      {:ok, left, ["^" | rest]} ->
        case parse_power(rest) do
          {:ok, right, rem} -> {:ok, %AST.BinOp{op: :^, left: left, right: right}, rem}
          err -> err
        end
      result -> result
    end
  end

  defp parse_unary(["!" | rest]) do
    case parse_unary(rest) do
      {:ok, e, rem} -> {:ok, %AST.UnaryOp{op: :!, expr: e}, rem}
      err -> err
    end
  end
  defp parse_unary(["-" | rest]) do
    case parse_unary(rest) do
      {:ok, e, rem} -> {:ok, %AST.UnaryOp{op: :-, expr: e}, rem}
      err -> err
    end
  end
  defp parse_unary(["@" | rest]) do
    case parse_unary(rest) do
      {:ok, e, rem} -> {:ok, %AST.UnaryOp{op: :@, expr: e}, rem}
      err -> err
    end
  end
  defp parse_unary(tokens), do: parse_primary(tokens)

  defp parse_primary([]), do: {:error, :unexpected_end}
  defp parse_primary([token | rest]) do
    cond do
      token == "(" -> handle_paren_expr(rest)
      token == "{" -> handle_list_expr(rest)
      token == "ANY" -> {:ok, :ANY, rest}
      token == "$" -> parse_suffix(%AST.Var{name: "$"}, rest)
      token == "?" ->
        case rest do
          [name | tail] -> {:ok, %AST.OptionalVar{name: name}, tail}
          _ -> {:error, :expected_identifier}
        end
      String.starts_with?(token, "$") ->
        name = String.slice(token, 1..-1//1)
        parse_suffix(%AST.PropRef{obj: %AST.Literal{value: {:obj, 0}}, prop: name}, rest)
      String.starts_with?(token, "#") ->
        case Integer.parse(String.slice(token, 1..-1//1)) do
          {num, ""} -> parse_suffix(%AST.Literal{value: Value.obj(num)}, rest)
          _ -> {:error, {:invalid_object_id, token}}
        end
      String.starts_with?(token, "\"") ->
        str = String.slice(token, 1, String.length(token) - 2) |> unescape_string()
        parse_suffix(%AST.Literal{value: Value.str(str)}, rest)
      Regex.match?(~r/^-?(?:\d+\.\d+|\.\d+)(?:[eE][+-]?\d+)?$/, token) or
      Regex.match?(~r/^-?\d+[eE][+-]?\d+$/, token) ->
        {val, _} = Float.parse(token)
        parse_suffix(%AST.Literal{value: {:float, val}}, rest)
      Regex.match?(~r/^-?\d+$/, token) ->
        parse_suffix(%AST.Literal{value: Value.num(String.to_integer(token))}, rest)
      token == "`" -> parse_backtick_catch(rest)
      Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, token) ->
        handle_call_or_var(token, rest)
      true -> {:error, {:unexpected_token, token}}
    end
  end

  defp parse_backtick_catch(tokens) do
    case parse_expr(tokens) do
      {:ok, e, ["!" | rest]} ->
        case parse_catch_codes(rest) do
          {:ok, codes, ["=>" | d_rest]} ->
            case parse_expr(d_rest) do
              {:ok, def_v, ["'" | rem]} -> {:ok, %AST.Catch{expr: e, codes: codes, default: def_v}, rem}
              _ -> {:error, :expected_closing_quote}
            end
          {:ok, codes, ["'" | rem]} -> {:ok, %AST.Catch{expr: e, codes: codes}, rem}
          _ -> {:error, :expected_closing_quote}
        end
      {:ok, e, ["'" | rem]} -> {:ok, %AST.Catch{expr: e}, rem}
      err -> err
    end
  end

  defp parse_catch_codes(["ANY" | rest]), do: {:ok, :ANY, rest}
  defp parse_catch_codes(tokens), do: parse_expr(tokens)

  defp handle_paren_expr(tokens) do
    case parse_expr(tokens) do
      {:ok, e, [")" | rem]} -> parse_suffix(e, rem)
      _ -> {:error, :expected_closing_paren}
    end
  end

  defp handle_call_or_var(name, ["(" | rest]) do
    case parse_args(rest) do
      {:ok, args, rem} -> parse_suffix(%AST.FuncCall{name: name, args: args}, rem)
      err -> err
    end
  end
  defp handle_call_or_var(name, rest), do: parse_suffix(%AST.Var{name: name}, rest)

  defp parse_suffix(node, ["." | rest]) do
    case rest do
      ["(" | tail] ->
        case parse_expr(tail) do
          {:ok, e, [")" | rem]} -> parse_suffix(%AST.PropRef{obj: node, prop: e}, rem)
          _ -> {:error, :expected_closing_paren}
        end
      [p | tail] ->
        if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, p) do
          parse_suffix(%AST.PropRef{obj: node, prop: p}, tail)
        else
          if String.starts_with?(p, "$") do
             parse_suffix(%AST.PropRef{obj: node, prop: String.slice(p, 1..-1//1)}, tail)
          else
             {:ok, node, ["." | rest]}
          end
        end
      _ -> {:error, :expected_property}
    end
  end

  defp parse_suffix(node, [":" | rest]) do
    target = case rest do
      ["(" | tail] ->
        case parse_expr(tail) do
          {:ok, e, [")" | rem]} -> {e, rem}
          _ -> nil
        end
      [v | tail] -> {v, tail}
      _ -> nil
    end

    case target do
      {v, ["(" | a_rest]} ->
        case parse_args(a_rest) do
          {:ok, args, rem} -> parse_suffix(%AST.VerbCall{obj: node, verb: v, args: args}, rem)
          err -> err
        end
      _ -> {:ok, node, [":" | rest]}
    end
  end

  defp parse_suffix(node, ["!" | rest]) do
    # Only initiate a catch suffix if we are at the right precedence
    case parse_catch_codes(rest) do
      {:ok, codes, ["=>" | d_rest]} ->
        case parse_expr(d_rest) do
          {:ok, def_v, rem} -> {:ok, %AST.Catch{expr: node, codes: codes, default: def_v}, rem}
          err -> err
        end
      {:ok, codes, rem} -> {:ok, %AST.Catch{expr: node, codes: codes}, rem}
      _ -> {:ok, node, ["!" | rest]}
    end
  end

  defp parse_suffix(node, ["[" | rest]) do
    case parse_expr(rest) do
      {:ok, s, [".." | tail]} ->
        case parse_expr(tail) do
          {:ok, e, ["]" | rem]} -> parse_suffix(%AST.Range{expr: node, start: s, end: e}, rem)
          _ -> {:error, :expected_closing_bracket}
        end
      {:ok, i, ["]" | rem]} -> parse_suffix(%AST.Index{expr: node, index: i}, rem)
      err -> err
    end
  end
  defp parse_suffix(node, rest), do: {:ok, node, rest}

  defp parse_args([")" | rest]), do: {:ok, [], rest}
  defp parse_args(tokens) do
    case parse_expr(tokens) do
      {:ok, a, ["," | rest]} ->
        case parse_args(rest) do
          {:ok, args, rem} -> {:ok, [a | args], rem}
          err -> err
        end
      {:ok, a, [")" | rest]} -> {:ok, [a], rest}
      _ -> {:error, :expected_closing_paren}
    end
  end

  defp handle_list_expr(["}" | rest]), do: parse_suffix(%AST.ListExpr{elements: []}, rest)
  defp handle_list_expr(tokens) do
    case parse_list_elements(tokens) do
      {:ok, es, ["}" | rest]} -> parse_suffix(%AST.ListExpr{elements: es}, rest)
      _ -> {:error, :expected_closing_brace}
    end
  end

  defp parse_list_elements(tokens) do
    case parse_primary(tokens) do
      {:ok, %AST.OptionalVar{} = v, ["=" | rest]} ->
        case parse_expr(rest) do
          {:ok, d, ["," | rem]} ->
            case parse_list_elements(rem) do
              {:ok, tail, f} -> {:ok, [%{v | default: d} | tail], f}
              err -> err
            end
          {:ok, d, ["}" | _] = rem} -> {:ok, [%{v | default: d}], rem}
          err -> err
        end
      {:ok, %AST.OptionalVar{} = v, ["," | rest]} ->
        case parse_list_elements(rest) do
          {:ok, t, f} -> {:ok, [v | t], f}
          err -> err
        end
      {:ok, %AST.OptionalVar{} = v, ["}" | _] = rem} -> {:ok, [v], rem}
      _ ->
        case parse_expr(tokens) do
          {:ok, e, ["," | rest]} ->
            case parse_list_elements(rest) do
              {:ok, t, f} -> {:ok, [e | t], f}
              err -> err
            end
          {:ok, e, ["}" | _] = rem} -> {:ok, [e], rem}
          err -> err
        end
    end
  end

  defp unescape_string(s) do
    s
    |> String.replace("\\\\", "\0")
    |> String.replace("\\\"", "\"")
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\0", "\\")
  end
end
