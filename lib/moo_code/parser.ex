defmodule Alchemoo.MOOCode.Parser do
  @moduledoc """
  Unified recursive descent parser for MOO code.
  Works with token streams from the lexer.
  No regex - pure pattern matching.
  """

  alias Alchemoo.MOOCode.AST
  alias Alchemoo.MOOCode.Parser.Lexer
  alias Alchemoo.Value

  @comparison_ops [:==, :!=, :<, :>, :<=, :>=, :in]
  @additive_ops [:+, :-]
  @multiplicative_ops [:*, :/, :%]

  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  @doc """
  Parse MOO source code into an AST.
  """
  def parse(source) when is_binary(source) do
    with {:ok, tokens} <- Lexer.lex(source),
         {:ok, block, []} <- parse_block(tokens, []) do
      {:ok, block}
    else
      {:ok, _block, [extra | _]} -> {:error, {:unexpected_token, extra}}
      err -> err
    end
  end

  def parse(tokens) when is_list(tokens) do
    case parse_block(tokens, []) do
      {:ok, block, []} -> {:ok, block}
      {:ok, _block, [extra | _]} -> {:error, {:unexpected_token, extra}}
      err -> err
    end
  end

  # --- Block Parsing ---

  defp parse_block(tokens, terminators) do
    case do_parse_block(tokens, terminators, []) do
      {:ok, statements, remaining} ->
        {:ok, %AST.Block{statements: Enum.reverse(statements)}, remaining}

      err ->
        err
    end
  end

  defp do_parse_block(tokens, terminators, acc) do
    cond do
      match_terminator?(tokens, terminators) -> {:ok, acc, tokens}
      tokens == [] -> {:ok, acc, tokens}
      end_of_input?(tokens) -> {:error, {:missing_closer, hd(terminators)}}
      true -> parse_next_statement(tokens, terminators, acc)
    end
  end

  defp match_terminator?(tokens, terminators) do
    case peek(tokens) do
      {:keyword, kw, _} -> kw in terminators
      _ -> false
    end
  end

  defp end_of_input?(tokens), do: peek(tokens) == nil

  defp parse_next_statement(tokens, terminators, acc) do
    case parse_statement(tokens) do
      {:ok, stmt, remaining} -> do_parse_block(remaining, terminators, [stmt | acc])
      err -> err
    end
  end

  # --- Statement Parsing ---

  defp parse_statement(tokens) do
    case peek(tokens) do
      {:keyword, :if, _} -> parse_if(tokens)
      {:keyword, :while, _} -> parse_while(tokens)
      {:keyword, :for, _} -> parse_for(tokens)
      {:keyword, :return, _} -> parse_return(tokens)
      {:keyword, :break, _} -> parse_break(tokens)
      {:keyword, :continue, _} -> parse_continue(tokens)
      {:keyword, :try, _} -> parse_try(tokens)
      _ -> parse_expr_statement(tokens)
    end
  end

  defp parse_break([{:keyword, :break, _} | rest]), do: {:ok, %AST.Break{}, skip_semi(rest)}

  defp parse_continue([{:keyword, :continue, _} | rest]),
    do: {:ok, %AST.Continue{}, skip_semi(rest)}

  # --- If Statement ---

  defp parse_if([{:keyword, :if, _} | rest]) do
    with {:ok, condition, rest2} <- parse_paren_expr(rest),
         {:ok, then_block, rest3} <- parse_block(rest2, [:elseif, :else, :endif]) do
      parse_if_rest(condition, then_block, [], rest3)
    end
  end

  defp parse_if_rest(condition, then_block, elseifs, tokens) do
    case peek(tokens) do
      {:keyword, :elseif, _} -> parse_elseif(condition, then_block, elseifs, tokens)
      {:keyword, :else, _} -> parse_else(condition, then_block, elseifs, tokens)
      {:keyword, :endif, _} -> finalize_if(condition, then_block, elseifs, tokens)
      _ -> {:error, {:expected_endif, peek_pos(tokens)}}
    end
  end

  defp parse_elseif(condition, then_block, elseifs, [_ | rest]) do
    with {:ok, elseif_cond, rest1} <- parse_paren_expr(rest),
         {:ok, elseif_body, rest2} <- parse_block(rest1, [:elseif, :else, :endif]) do
      elseif_node = %AST.ElseIf{condition: elseif_cond, block: elseif_body}
      parse_if_rest(condition, then_block, elseifs ++ [elseif_node], rest2)
    end
  end

  defp parse_elseif(_condition, _then_block, _elseifs, []), do: {:error, :expected_endif}

  defp parse_else(condition, then_block, elseifs, [_ | rest]) do
    with {:ok, else_block, rest1} <- parse_block(rest, [:endif]),
         [{:keyword, :endif, _} | remaining] <- rest1 do
      {:ok,
       %AST.If{
         condition: condition,
         then_block: then_block,
         elseif_blocks: elseifs,
         else_block: else_block
       }, remaining}
    else
      _ -> {:error, :expected_endif}
    end
  end

  defp parse_else(_condition, _then_block, _elseifs, []), do: {:error, :expected_endif}

  defp finalize_if(condition, then_block, elseifs, [_ | remaining]) do
    {:ok,
     %AST.If{
       condition: condition,
       then_block: then_block,
       elseif_blocks: elseifs,
       else_block: nil
     }, remaining}
  end

  # --- While Loop ---

  defp parse_while([{:keyword, :while, _} | rest]) do
    with {:ok, condition, rest2} <- parse_paren_expr(rest),
         {:ok, body, rest3} <- parse_block(rest2, [:endwhile]),
         [{:keyword, :endwhile, _} | remaining] <- rest3 do
      {:ok, %AST.While{condition: condition, body: body}, remaining}
    else
      _ -> {:error, :expected_endwhile}
    end
  end

  # --- For Loop ---

  defp parse_for([{:keyword, :for, _} | rest]) do
    case parse_for_header(rest) do
      {:ok, var, range_expr, rest2} ->
        with {:ok, body, rest3} <- parse_block(rest2, [:endfor]),
             [{:keyword, :endfor, _} | remaining] <- rest3 do
          {:ok, build_for_ast(var, range_expr, body), remaining}
        else
          _ -> {:error, :expected_endfor}
        end

      err ->
        err
    end
  end

  defp parse_for_header([{:ident, var, _}, {:op, :in, _} | rest]) do
    case parse_expr(rest) do
      {:ok, range_expr, rest3} -> {:ok, var, range_expr, rest3}
      err -> err
    end
  end

  defp parse_for_header(_), do: {:error, :invalid_for_header}

  defp build_for_ast(var, %AST.Range{} = range, body),
    do: %AST.For{var: var, range: range, body: body}

  defp build_for_ast(var, range_expr, body),
    do: %AST.ForList{var: var, list: range_expr, body: body}

  # --- Return Statement ---

  defp parse_return([{:keyword, :return, _} | rest]) do
    case peek(rest) do
      {:semi, _, _} -> {:ok, return_zero(), tl(rest)}
      nil -> {:ok, return_zero(), rest}
      _ -> parse_return_expr(rest)
    end
  end

  defp return_zero, do: %AST.Return{value: %AST.Literal{value: Value.num(0)}}

  defp parse_return_expr(rest) do
    with {:ok, value, rest2} <- parse_expr(rest) do
      {:ok, %AST.Return{value: value}, skip_semi(rest2)}
    end
  end

  # --- Try Statement ---

  defp parse_try([{:keyword, :try, _} | rest]) do
    with {:ok, body, rest2} <- parse_block(rest, [:except, :finally, :endtry]) do
      parse_try_rest(body, rest2, [])
    end
  end

  defp parse_try_rest(body, tokens, excepts) do
    case peek(tokens) do
      {:keyword, :except, _} -> parse_except_clause(body, tokens, excepts)
      {:keyword, :finally, _} -> parse_finally_clause(body, tokens, excepts)
      {:keyword, :endtry, _} -> finalize_try(body, excepts, tokens)
      _ -> {:error, {:expected_endtry, peek_pos(tokens)}}
    end
  end

  defp parse_except_clause(body, tokens, excepts) do
    with {:ok, var, codes, rest1} <- parse_except_header(tokens),
         {:ok, except_body, rest2} <- parse_block(rest1, [:except, :finally, :endtry]) do
      clause = %AST.Except{error_var: var, codes: codes, body: except_body}
      parse_try_rest(body, rest2, excepts ++ [clause])
    end
  end

  defp parse_finally_clause(body, [_ | rest], excepts) do
    with {:ok, finally_body, rest1} <- parse_block(rest, [:endtry]),
         [{:keyword, :endtry, _} | remaining] <- rest1 do
      {:ok, %AST.Try{body: body, except_clauses: excepts, finally_block: finally_body}, remaining}
    else
      _ -> {:error, :expected_endtry}
    end
  end

  defp finalize_try(body, excepts, [_ | remaining]) do
    {:ok, %AST.Try{body: body, except_clauses: excepts, finally_block: nil}, remaining}
  end

  defp parse_except_header([{:keyword, :except, _} | rest]) do
    case peek(rest) do
      {:any, :ANY} -> {:ok, nil, :ANY, rest}
      {:ident, var, _} -> parse_except_var(var, rest)
      {:lparen, _, _} -> parse_except_codes(rest)
      _ -> {:error, :invalid_except_header}
    end
  end

  defp parse_except_var(var, [{:ident, var, _}, {:lparen, _, _} = lparen | rest]) do
    with {:ok, codes, rest2} <- parse_paren_expr([lparen | rest]) do
      {:ok, var, normalize_codes(codes), rest2}
    end
  end

  defp parse_except_var(var, [{:ident, var, _} | rest]), do: {:ok, var, :ANY, rest}

  defp parse_except_codes([{:lparen, _, _} | rest]) do
    # Parse comma-separated list of error codes
    case parse_except_code_list(rest, []) do
      {:ok, codes, [{:rparen, _, _} | rest2]} ->
        normalized = normalize_except_codes(codes)
        {:ok, nil, normalized, rest2}

      err ->
        err
    end
  end

  defp parse_except_codes(rest) do
    with {:ok, codes, rest2} <- parse_paren_expr(rest) do
      {:ok, nil, normalize_codes(codes), rest2}
    end
  end

  defp parse_except_code_list(tokens, acc) do
    case peek(tokens) do
      {:rparen, _, _} ->
        {:ok, Enum.reverse(acc), tokens}

      {:comma, _, _} ->
        case tokens do
          [_comma | rest] -> parse_except_code_list(rest, acc)
          [] -> {:error, :expected_except_code}
        end

      _ ->
        case parse_expr(tokens) do
          {:ok, code, rest} -> parse_except_code_list(rest, [code | acc])
          err -> err
        end
    end
  end

  defp normalize_except_codes([single]), do: single
  defp normalize_except_codes(codes) when is_list(codes), do: %AST.ListExpr{elements: codes}

  defp normalize_codes(:ANY), do: :ANY
  defp normalize_codes(codes), do: codes

  # --- Expression Statement ---

  defp parse_expr_statement(tokens) do
    with {:ok, expr, rest} <- parse_expr(tokens) do
      {:ok, %AST.ExprStmt{expr: expr}, skip_semi(rest)}
    end
  end

  defp skip_semi([{:semi, _, _} | rest]), do: rest
  defp skip_semi(tokens), do: tokens

  # --- Paren Expression Helper ---

  defp parse_paren_expr([{:lparen, _, _} | rest]) do
    with {:ok, expr, [{:rparen, _, _} | remaining]} <- parse_expr(rest) do
      {:ok, expr, remaining}
    end
  end

  defp parse_paren_expr(_tokens), do: {:error, :expected_paren}

  # --- Expression Parsing (Precedence Climbing) ---

  defp parse_expr(tokens), do: parse_catch(tokens)

  defp parse_catch(tokens) do
    with {:ok, expr, rest} <- parse_assignment(tokens) do
      case rest do
        [{:op, :!, _} | rest2] -> parse_catch_suffix(expr, rest2)
        _ -> {:ok, expr, rest}
      end
    end
  end

  defp parse_assignment(tokens) do
    with {:ok, left, rest} <- parse_splice(tokens) do
      case rest do
        [{:op, :=, _} | rest2] ->
          with {:ok, right, remaining} <- parse_assignment(rest2) do
            {:ok, %AST.Assignment{target: left, value: right}, remaining}
          end

        _ ->
          {:ok, left, rest}
      end
    end
  end

  defp parse_splice(tokens) do
    case tokens do
      [{:op, :@, _} | rest] ->
        # @ splice operator - lower precedence than ternary
        with {:ok, expr, remaining} <- parse_ternary(rest) do
          {:ok, %AST.UnaryOp{op: :@, expr: expr}, remaining}
        end

      _ ->
        parse_ternary(tokens)
    end
  end

  defp parse_ternary(tokens) do
    with {:ok, condition, rest} <- parse_logical_or(tokens) do
      case rest do
        [{:op, :"?", _} | rest2] -> parse_ternary_rest(condition, rest2)
        _ -> {:ok, condition, rest}
      end
    end
  end

  defp parse_ternary_rest(condition, rest2) do
    with {:ok, then_e, [{:op, :|, _} | rest3]} <- parse_expr(rest2),
         {:ok, else_e, remaining} <- parse_expr(rest3) do
      {:ok, %AST.Conditional{condition: condition, then_expr: then_e, else_expr: else_e},
       remaining}
    end
  end

  defp parse_logical_or(tokens), do: parse_logical_op(tokens, :||, &parse_logical_and/1)
  defp parse_logical_and(tokens), do: parse_logical_op(tokens, :&&, &parse_comparison/1)

  defp parse_logical_op(tokens, op, next_level) do
    with {:ok, left, rest} <- next_level.(tokens) do
      case rest do
        [{:op, ^op, _} | rest2] ->
          with {:ok, right, remaining} <- parse_logical_op(rest2, op, next_level) do
            {:ok, %AST.BinOp{op: op, left: left, right: right}, remaining}
          end

        _ ->
          {:ok, left, rest}
      end
    end
  end

  defp parse_comparison(tokens) do
    with {:ok, left, rest} <- parse_additive(tokens) do
      case rest do
        [{:op, op, _} | rest2] ->
          if op in @comparison_ops do
            with {:ok, right, remaining} <- parse_additive(rest2) do
              {:ok, %AST.BinOp{op: op, left: left, right: right}, remaining}
            end
          else
            {:ok, left, rest}
          end

        _ ->
          {:ok, left, rest}
      end
    end
  end

  defp parse_additive(tokens), do: parse_binary_op(tokens, @additive_ops, &parse_multiplicative/1)

  defp parse_multiplicative(tokens),
    do: parse_binary_op(tokens, @multiplicative_ops, &parse_power/1)

  defp parse_binary_op(tokens, ops, next_level) do
    with {:ok, left, rest} <- next_level.(tokens) do
      case rest do
        [{:op, op, _} | rest2] ->
          if op in ops do
            with {:ok, right, remaining} <- parse_binary_op(rest2, ops, next_level) do
              {:ok, %AST.BinOp{op: op, left: left, right: right}, remaining}
            end
          else
            {:ok, left, rest}
          end

        _ ->
          {:ok, left, rest}
      end
    end
  end

  defp parse_power(tokens) do
    with {:ok, left, rest} <- parse_unary(tokens) do
      case rest do
        [{:op, :^, _} | rest2] ->
          with {:ok, right, remaining} <- parse_power(rest2) do
            {:ok, %AST.BinOp{op: :^, left: left, right: right}, remaining}
          end

        _ ->
          {:ok, left, rest}
      end
    end
  end

  defp parse_unary([{:op, op, _} | rest]) when op in [:!, :-] do
    with {:ok, expr, remaining} <- parse_unary(rest) do
      {:ok, %AST.UnaryOp{op: op, expr: expr}, remaining}
    end
  end

  defp parse_unary(tokens), do: parse_primary(tokens)

  # --- Primary Expressions ---

  defp parse_primary([{:lparen, _, _} | rest]) do
    with {:ok, expr, [{:rparen, _, _} | remaining]} <- parse_expr(rest) do
      parse_suffix(expr, remaining)
    end
  end

  defp parse_primary([{:lbracket, _, _} | rest]) do
    with {:ok, start, rest2} <- parse_expr(rest),
         [{:op, :.., _} | rest3] <- rest2,
         {:ok, ending, [{:rbracket, _, _} | remaining]} <- parse_expr(rest3) do
      parse_suffix(%AST.Range{start: start, end: ending}, remaining)
    else
      _ -> {:error, :invalid_range}
    end
  end

  defp parse_primary([{:lbrace, _, _} | rest]), do: parse_list(rest)

  defp parse_primary([{:int, n, _} | rest]),
    do: parse_suffix(%AST.Literal{value: Value.num(n)}, rest)

  defp parse_primary([{:float, f, _} | rest]),
    do: parse_suffix(%AST.Literal{value: {:float, f}}, rest)

  defp parse_primary([{:string, s, _} | rest]),
    do: parse_suffix(%AST.Literal{value: Value.str(s)}, rest)

  defp parse_primary([{:obj, n, _} | rest]),
    do: parse_suffix(%AST.Literal{value: Value.obj(n)}, rest)

  defp parse_primary([{:global, name, _} | rest]) do
    parse_suffix(%AST.PropRef{obj: %AST.Literal{value: {:obj, 0}}, prop: name}, rest)
  end

  defp parse_primary([{:dollar, :"$", _} | rest]), do: parse_suffix(%AST.Var{name: "$"}, rest)
  defp parse_primary([{:any, :ANY, _} | rest]), do: {:ok, :ANY, rest}

  defp parse_primary([{:optional, name, _} | rest]),
    do: parse_suffix(%AST.OptionalVar{name: name}, rest)

  defp parse_primary([{:ident, "optional", _}, {:ident, name, _} | rest]) do
    parse_suffix(%AST.OptionalVar{name: name}, rest)
  end

  defp parse_primary([{:ident, name, _} | rest]) do
    case rest do
      [{:lparen, _, _} | _] -> parse_func_call(name, rest)
      _ -> parse_suffix(%AST.Var{name: name}, rest)
    end
  end

  defp parse_primary([{:backtick, _, _} | rest]), do: parse_catch_expr(rest)
  defp parse_primary([]), do: {:error, :unexpected_end}
  defp parse_primary([token | _]), do: {:error, {:unexpected_token, token}}

  defp parse_func_call(name, rest) do
    with {:ok, args, [{:rparen, _, _} | remaining]} <- parse_arg_list(rest) do
      parse_suffix(%AST.FuncCall{name: name, args: args}, remaining)
    end
  end

  # --- List Parsing ---

  defp parse_list([{:rbrace, _, _} | remaining]) do
    {:ok, %AST.ListExpr{elements: []}, remaining}
  end

  defp parse_list(tokens) do
    case parse_list_elements(tokens) do
      {:ok, elements, [{:rbrace, _, _} | remaining]} ->
        parse_suffix(%AST.ListExpr{elements: elements}, remaining)

      err ->
        err
    end
  end

  defp parse_list_elements(tokens), do: do_parse_list_elements(tokens, [])

  defp do_parse_list_elements(tokens, acc) do
    case peek(tokens) do
      {:rbrace, _, _} -> {:ok, Enum.reverse(acc), tokens}
      {:comma, _, _} -> skip_comma_in_list(tokens, acc)
      _ -> parse_list_element(tokens, acc)
    end
  end

  defp skip_comma_in_list([_comma | rest], acc), do: do_parse_list_elements(rest, acc)
  defp skip_comma_in_list([], _acc), do: {:error, :expected_list_element}

  defp parse_list_element(tokens, acc) do
    case parse_optional_element(tokens) do
      {:ok, elem, rest} -> do_parse_list_elements(rest, [elem | acc])
      err -> err
    end
  end

  defp parse_optional_element(tokens) do
    case tokens do
      [{:optional, name, _}, {:op, :=, _} | rest] ->
        with {:ok, default, remaining} <- parse_expr(rest) do
          {:ok, %AST.OptionalVar{name: name, default: default}, remaining}
        end

      [{:optional, name, _} | rest] ->
        {:ok, %AST.OptionalVar{name: name}, rest}

      [{:ident, "optional", _}, {:ident, name, _}, {:op, :=, _} | rest] ->
        with {:ok, default, remaining} <- parse_expr(rest) do
          {:ok, %AST.OptionalVar{name: name, default: default}, remaining}
        end

      [{:ident, "optional", _}, {:ident, name, _} | rest] ->
        {:ok, %AST.OptionalVar{name: name}, rest}

      _ ->
        parse_expr(tokens)
    end
  end

  # --- Argument List Parsing ---

  defp parse_arg_list([{:lparen, _, _} | rest]), do: parse_args(rest, [])

  defp parse_args(tokens, acc) do
    case peek(tokens) do
      {:rparen, _, _} -> {:ok, Enum.reverse(acc), tokens}
      {:comma, _, _} -> skip_comma_in_args(tokens, acc)
      _ -> parse_arg(tokens, acc)
    end
  end

  defp skip_comma_in_args([_comma | rest], acc), do: parse_args(rest, acc)
  defp skip_comma_in_args([], _acc), do: {:error, :expected_argument}

  defp parse_arg(tokens, acc) do
    with {:ok, arg, rest} <- parse_expr(tokens) do
      case rest do
        [{:comma, _, _} | rest2] -> parse_args(rest2, [arg | acc])
        [{:rparen, _, _} | _] -> {:ok, Enum.reverse([arg | acc]), rest}
        _ -> {:error, :expected_closing_paren}
      end
    end
  end

  # --- Catch Expression ---

  defp parse_catch_expr(tokens) do
    with {:ok, expr, rest} <- parse_expr(tokens) do
      case rest do
        [{:squote, _, _} | remaining] -> {:ok, expr, remaining}
        _ -> {:ok, expr, rest}
      end
    end
  end

  defp parse_catch_suffix(expr, tokens), do: parse_catch_codes(expr, tokens)

  defp parse_catch_codes(expr, tokens) do
    case peek(tokens) do
      {:any, :ANY} -> parse_any_catch(expr, tokens)
      _ -> parse_codes_catch(expr, tokens)
    end
  end

  defp parse_any_catch(expr, [{:any, :ANY}, {:squote, _, _} | rest]) do
    {:ok, %AST.Catch{expr: expr, codes: :ANY}, rest}
  end

  defp parse_any_catch(expr, [{:any, :ANY}, {:op, :"=>", _} | rest]) do
    with {:ok, default, remaining} <- parse_expr(rest) do
      result = %AST.Catch{expr: expr, codes: :ANY, default: default}
      {:ok, result, consume_catch_closer(remaining)}
    end
  end

  defp parse_any_catch(expr, [{:any, :ANY} | rest]) do
    with {:ok, default, remaining} <- parse_expr(rest) do
      {:ok, %AST.Catch{expr: expr, codes: :ANY, default: default}, skip_semi(remaining)}
    end
  end

  defp parse_any_catch(_expr, _tokens), do: {:error, :expected_closing_quote}

  defp parse_codes_catch(expr, tokens) do
    with {:ok, codes, rest} <- parse_catch_codes_list(tokens) do
      case rest do
        [{:op, :"=>", _} | rest2] -> parse_catch_default(expr, codes, rest2)
        [{:squote, _, _} | remaining] -> {:ok, %AST.Catch{expr: expr, codes: codes}, remaining}
        _ -> {:ok, %AST.Catch{expr: expr, codes: codes}, skip_semi(rest)}
      end
    end
  end

  defp parse_catch_codes_list(tokens) do
    # Parse comma-separated list of error codes for catch expression
    parse_catch_codes_list(tokens, [])
  end

  defp parse_catch_codes_list(tokens, acc) do
    case peek(tokens) do
      {:op, :"=>", _} ->
        {:ok, normalize_catch_codes(Enum.reverse(acc)), tokens}

      {:squote, _, _} ->
        {:ok, normalize_catch_codes(Enum.reverse(acc)), tokens}

      {:comma, _, _} ->
        case tokens do
          [_comma | rest] -> parse_catch_codes_list(rest, acc)
          [] -> {:error, :expected_catch_code}
        end

      _ ->
        case parse_expr(tokens) do
          {:ok, code, rest} -> parse_catch_codes_list(rest, [code | acc])
          err -> err
        end
    end
  end

  defp normalize_catch_codes([single]), do: single
  defp normalize_catch_codes(codes) when is_list(codes), do: %AST.ListExpr{elements: codes}

  defp parse_catch_default(expr, codes, rest2) do
    with {:ok, default, remaining} <- parse_expr(rest2) do
      result = %AST.Catch{expr: expr, codes: codes, default: default}
      {:ok, result, consume_catch_closer(remaining)}
    end
  end

  defp consume_catch_closer([{:squote, _, _} | rest]), do: rest
  defp consume_catch_closer(remaining), do: skip_semi(remaining)

  # --- Suffix Parsing ---

  defp parse_suffix(node, tokens) do
    case peek(tokens) do
      {:dot, _, _} -> parse_dot_suffix(node, tokens)
      {:colon, _, _} -> parse_colon_suffix(node, tokens)
      {:lbracket, _, _} -> parse_bracket_suffix(node, tokens)
      _ -> {:ok, node, tokens}
    end
  end

  defp parse_dot_suffix(node, [{:dot, _, _}, {:lparen, _, _} | rest]) do
    with {:ok, prop, [{:rparen, _, _} | rest2]} <- parse_expr(rest) do
      parse_suffix(%AST.PropRef{obj: node, prop: prop}, rest2)
    end
  end

  defp parse_dot_suffix(node, [{:dot, _, _}, {:ident, prop, _} | rest]) do
    parse_suffix(%AST.PropRef{obj: node, prop: prop}, rest)
  end

  defp parse_dot_suffix(node, [{:dot, _, _}, {:global, prop, _} | rest]) do
    parse_suffix(%AST.PropRef{obj: node, prop: prop}, rest)
  end

  defp parse_dot_suffix(_node, _tokens), do: {:ok, nil, []}

  defp parse_colon_suffix(node, [{:colon, _, _}, {:lparen, _, _} | rest]) do
    with {:ok, verb, [{:rparen, _, _} | rest2]} <- parse_expr(rest) do
      parse_verb_call(node, verb, rest2)
    end
  end

  defp parse_colon_suffix(node, [{:colon, _, _}, {:ident, verb, _} | rest]) do
    case rest do
      [{:lparen, _, _} | _] -> parse_verb_call_args(node, verb, rest)
      _ -> {:ok, node, []}
    end
  end

  defp parse_colon_suffix(_node, _tokens), do: {:ok, nil, []}

  defp parse_verb_call(node, verb, [{:lparen, _, _} | _] = rest2) do
    parse_verb_call_args(node, verb, rest2)
  end

  defp parse_verb_call(node, verb, rest2) do
    parse_suffix(%AST.VerbCall{obj: node, verb: verb, args: []}, rest2)
  end

  defp parse_verb_call_args(node, verb, rest) do
    with {:ok, args, [{:rparen, _, _} | remaining]} <- parse_arg_list(rest) do
      parse_suffix(%AST.VerbCall{obj: node, verb: verb, args: args}, remaining)
    end
  end

  defp parse_bracket_suffix(node, [{:lbracket, _, _} | rest]) do
    with {:ok, idx, rest2} <- parse_expr(rest) do
      case rest2 do
        [{:op, :.., _} | rest3] ->
          parse_range_suffix(node, idx, rest3)

        [{:rbracket, _, _} | remaining] ->
          parse_suffix(%AST.Index{expr: node, index: idx}, remaining)

        _ ->
          {:error, :expected_closing_bracket}
      end
    end
  end

  defp parse_bracket_suffix(_node, _tokens), do: {:ok, nil, []}

  defp parse_range_suffix(node, idx, rest3) do
    with {:ok, end_idx, [{:rbracket, _, _} | remaining]} <- parse_expr(rest3) do
      parse_suffix(%AST.Range{expr: node, start: idx, end: end_idx}, remaining)
    end
  end

  # --- Token Utilities ---

  defp peek([]), do: nil
  defp peek([token | _]), do: token

  defp peek_pos([]), do: nil
  defp peek_pos([{_, _, pos} | _]), do: pos
  defp peek_pos([token | _]), do: {:unknown, token}
end
