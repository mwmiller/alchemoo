defmodule Alchemoo.Interpreter do
  @moduledoc """
  Simple tree-walking interpreter for MOO expressions.

  This evaluates AST nodes directly. A production interpreter would
  compile to bytecode first for better performance.
  """

  require Logger
  alias Alchemoo.AST
  alias Alchemoo.Value

  @doc """
  Evaluate a MOO expression AST with given environment.

  Environment can include:
  - Variable bindings (map of name => value)
  - :runtime key with Alchemoo.Runtime struct for object access

  ## Examples

      iex> eval(%AST.Literal{value: {:num, 42}}, %{})
      {:ok, {:num, 42}}
      
      iex> eval(%AST.BinOp{op: :+, left: ..., right: ...}, %{})
      {:ok, {:num, 3}}
  """
  def eval(ast, env \\ %{}) do
    consume_tick()
    do_eval(ast, env)
  end

  defp consume_tick do
    case Process.get(:ticks_remaining) do
      nil -> :ok
      n when n <= 0 -> throw(:quota_exceeded)
      n -> Process.put(:ticks_remaining, n - 1)
    end
  end

  defp do_eval(%AST.Literal{value: val}, _env) do
    {:ok, val}
  end

  defp do_eval(%AST.Var{name: name}, env) do
    case Map.get(env, name) do
      nil -> {:error, Value.err(:E_VARNF)}
      val -> {:ok, val}
    end
  end

  defp do_eval(%AST.BinOp{op: op, left: left, right: right}, env) do
    case op do
      :&& ->
        with {:ok, left_val} <- eval(left, env) do
          if Value.truthy?(left_val) do
            eval(right, env)
          else
            {:ok, left_val}
          end
        end

      :|| ->
        with {:ok, left_val} <- eval(left, env) do
          if Value.truthy?(left_val) do
            {:ok, left_val}
          else
            eval(right, env)
          end
        end

      _ ->
        with {:ok, left_val} <- eval(left, env),
             {:ok, right_val} <- eval(right, env) do
          eval_binop(op, left_val, right_val)
        end
    end
  end

  defp do_eval(%AST.UnaryOp{op: op, expr: expr}, env) do
    with {:ok, val} <- eval(expr, env) do
      eval_unop(op, val)
    end
  end

  defp do_eval(%AST.ListExpr{elements: elements}, env) do
    results =
      Enum.reduce_while(elements, {:ok, []}, fn elem, {:ok, acc} ->
        case eval(elem, env) do
          {:ok, {:spliced, list}} -> {:cont, {:ok, Enum.reverse(list) ++ acc}}
          {:ok, val} -> {:cont, {:ok, [val | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case results do
      {:ok, vals} -> {:ok, Value.list(Enum.reverse(vals))}
      error -> error
    end
  end

  defp do_eval(%AST.Index{expr: expr, index: index}, env) do
    with {:ok, coll} <- eval(expr, env),
         {:ok, idx} <- eval(index, env) do
      {:ok, Value.index(coll, idx)}
    end
  end

  defp do_eval(%AST.Range{expr: expr, start: start_expr, end: end_expr}, env) do
    with {:ok, coll} <- eval(expr, env),
         {:ok, {:num, start_idx}} <- eval(start_expr, env),
         {:ok, {:num, end_idx}} <- eval(end_expr, env) do
      {:ok, Value.range(coll, start_idx, end_idx)}
    end
  end

  defp do_eval(%AST.Conditional{condition: cond, then_expr: then_e, else_expr: else_e}, env) do
    with {:ok, cond_val} <- eval(cond, env) do
      if Value.truthy?(cond_val) do
        eval(then_e, env)
      else
        eval(else_e, env)
      end
    end
  end

  defp do_eval(%AST.FuncCall{name: name, args: arg_exprs}, env) do
    Logger.debug("Interpreter: calling builtin #{name}()")

    with {:ok, arg_vals} <- eval_args(arg_exprs, env) do
      result = Alchemoo.Builtins.call(name, arg_vals, env)
      {:ok, result}
    end
  end

  defp do_eval(%AST.PropRef{obj: obj_expr, prop: prop_name}, env) do
    with {:ok, obj_val} <- eval(obj_expr, env) do
      case Map.get(env, :runtime) do
        nil -> {:error, Value.err(:E_PERM)}
        runtime -> Alchemoo.Runtime.get_property(runtime, obj_val, prop_name)
      end
    end
  end

  defp do_eval(%AST.VerbCall{obj: obj_expr, verb: verb_name, args: arg_exprs}, env) do
    with {:ok, obj_val} <- eval(obj_expr, env),
         {:ok, arg_vals} <- eval_args(arg_exprs, env) do
      Logger.debug("Interpreter: calling verb #{Alchemoo.Value.to_literal(obj_val)}:#{verb_name}()")

      case Map.get(env, :runtime) do
        nil -> {:error, Value.err(:E_PERM)}
        runtime -> Alchemoo.Runtime.call_verb(runtime, obj_val, verb_name, arg_vals, env)
      end
    end
  end

  defp do_eval(%AST.Block{statements: stmts}, env) do
    Logger.debug("Interpreter: entering block with #{length(stmts)} statements")
    eval_block(stmts, env)
  end

  defp do_eval(
         %AST.If{condition: cond, then_block: then_b, elseif_blocks: elseifs, else_block: else_b},
         env
       ) do
    with {:ok, cond_val} <- eval(cond, env) do
      case Value.truthy?(cond_val) do
        true -> eval(then_b, env)
        false -> eval_elseifs(elseifs, else_b, env)
      end
    end
  end

  defp do_eval(%AST.While{condition: cond, body: body}, env) do
    eval_while(cond, body, env)
  end

  defp do_eval(%AST.ForList{var: var, list: list_expr, body: body}, env) do
    with {:ok, {:list, items}} <- eval(list_expr, env) do
      eval_for_list(var, items, body, env)
    end
  end

  defp do_eval(%AST.For{var: var, range: range_expr, body: body}, env) do
    with {:ok, range} <- eval(range_expr, env) do
      items =
        case range do
          {:list, items} -> items
          _ -> []
        end

      eval_for_list(var, items, body, env)
    end
  end

  defp do_eval(%AST.Return{value: val_expr}, env) do
    with {:ok, val} <- eval(val_expr, env) do
      throw({:return, val})
    end
  end

  defp do_eval(%AST.Break{}, _env) do
    throw(:break)
  end

  defp do_eval(%AST.Continue{}, _env) do
    throw(:continue)
  end

  defp do_eval(%AST.Assignment{target: target, value: val_expr}, env) do
    with {:ok, val} <- eval(val_expr, env) do
      perform_assignment(target, val, env)
    end
  end

  defp do_eval(%AST.Try{body: body, except_clauses: clauses}, env) do
    case eval(body, env) do
      {:error, err} -> handle_exception(err, clauses, env)
      other -> other
    end
  rescue
    e -> {:error, e}
  catch
    {:error, err} -> handle_exception(err, clauses, env)
  end

  defp do_eval(%AST.ExprStmt{expr: expr}, env) do
    eval(expr, env)
  end

  # Helper: perform assignment to various targets
  defp perform_assignment(%AST.Var{name: name}, val, env) do
    {:ok, val, Map.put(env, name, val)}
  end

  defp perform_assignment(%AST.PropRef{obj: obj_expr, prop: prop_name}, val, env) do
    with {:ok, obj_val} <- eval(obj_expr, env) do
      perform_prop_assignment(obj_val, prop_name, val, env)
    end
  end

  defp perform_assignment(%AST.Index{expr: target_expr, index: index_expr}, val, env) do
    with {:ok, coll} <- eval(target_expr, env),
         {:ok, idx} <- eval(index_expr, env) do
      case Value.set_index(coll, idx, val) do
        {:err, _} = err -> err
        new_coll -> perform_assignment(target_expr, new_coll, env)
      end
    end
  end

  defp perform_assignment(%AST.ListExpr{elements: targets}, {:list, values}, env) do
    case destructure_list(targets, values, env) do
      {:ok, new_env} -> {:ok, {:list, values}, new_env}
      err -> err
    end
  end

  defp perform_assignment(%AST.ListExpr{}, _, _env), do: {:error, Value.err(:E_TYPE)}

  defp destructure_list([], [], env), do: {:ok, env}
  defp destructure_list([], _, _env), do: {:error, Value.err(:E_ARGS)}

  defp destructure_list([%AST.UnaryOp{op: :@, expr: target} | rest_targets], values, env) do
    # Collect all remaining values into this target
    num_rest = length(rest_targets)
    {spliced_values, remaining_values} = Enum.split(values, length(values) - num_rest)

    with {:ok, _, env} <- perform_assignment(target, Value.list(spliced_values), env) do
      destructure_list(rest_targets, remaining_values, env)
    end
  end

  defp destructure_list([target | rest_targets], [val | rest_values], env) do
    with {:ok, _, env} <- perform_assignment(target, val, env) do
      destructure_list(rest_targets, rest_values, env)
    end
  end

  defp destructure_list([_ | _], [], _env), do: {:error, Value.err(:E_ARGS)}

  defp handle_exception(err, clauses, env) do
    case clauses do
      [clause | _] ->
        # Standard MOO error format for except: {code, message, value, traceback}
        # For now, just {code, "", 0, {}}
        err_value = Value.list([err, Value.str(""), Value.num(0), Value.list([])])
        except_env = Map.put(env, clause.error_var, err_value)
        eval(clause.body, except_env)

      [] ->
        throw({:error, err})
    end
  end

  defp perform_prop_assignment(obj_val, prop_name, val, env) do
    case Map.get(env, :runtime) do
      nil ->
        {:error, Value.err(:E_PERM)}

      runtime ->
        case Alchemoo.Runtime.set_property(runtime, obj_val, prop_name, val) do
          {:ok, val, new_runtime} ->
            {:ok, val, Map.put(env, :runtime, new_runtime)}

          {:error, _} = err ->
            err
        end
    end
  end

  # Helper: evaluate block of statements
  defp eval_block([], env), do: {:ok, Value.num(0), env}

  defp eval_block([stmt | rest], env) do
    case eval(stmt, env) do
      {:ok, _val, new_env} ->
        eval_block(rest, new_env)

      {:ok, val} ->
        case rest do
          [] -> {:ok, val}
          _ -> eval_block(rest, env)
        end

      {:error, _} = err ->
        err
    end
  end

  # Helper: evaluate elseif chains
  defp eval_elseifs([], nil, _env), do: {:ok, Value.num(0)}
  defp eval_elseifs([], else_block, env), do: eval(else_block, env)

  defp eval_elseifs([%AST.ElseIf{condition: cond, block: block} | rest], else_block, env) do
    with {:ok, cond_val} <- eval(cond, env) do
      case Value.truthy?(cond_val) do
        true -> eval(block, env)
        false -> eval_elseifs(rest, else_block, env)
      end
    end
  end

  defp eval_while(cond, body, env) do
    case eval(cond, env) do
      {:ok, cond_val} ->
        handle_while_loop(cond_val, cond, body, env)

      {:error, _} = err ->
        err
    end
  end

  defp handle_while_loop(cond_val, cond, body, env) do
    case Value.truthy?(cond_val) do
      true -> execute_while_body(cond, body, env)
      false -> {:ok, Value.num(0)}
    end
  end

  defp execute_while_body(cond, body, env) do
    case catch_loop_control(fn -> eval(body, env) end) do
      {:break, _} -> {:ok, Value.num(0)}
      {:continue, _} -> eval_while(cond, body, env)
      {:ok, _} -> eval_while(cond, body, env)
      {:ok, _, new_env} -> eval_while(cond, body, new_env)
      {:error, _} = err -> err
    end
  end

  # Helper: for-in loop
  defp eval_for_list(_var, [], _body, _env), do: {:ok, Value.num(0)}

  defp eval_for_list(var, [item | rest], body, env) do
    loop_env = Map.put(env, var, item)

    case catch_loop_control(fn -> eval(body, loop_env) end) do
      {:break, _} -> {:ok, Value.num(0)}
      {:continue, _} -> eval_for_list(var, rest, body, env)
      {:ok, _} -> eval_for_list(var, rest, body, env)
      {:ok, _, _} -> eval_for_list(var, rest, body, env)
      {:error, _} = err -> err
    end
  end

  # Helper: catch break/continue
  defp catch_loop_control(fun) do
    fun.()
  catch
    :break -> {:break, nil}
    :continue -> {:continue, nil}
    {:return, val} -> throw({:return, val})
  end

  defp eval_args(arg_exprs, env) do
    Enum.reduce_while(arg_exprs, {:ok, []}, fn expr, {:ok, acc} ->
      case eval(expr, env) do
        {:ok, {:spliced, {:list, list}}} -> {:cont, {:ok, Enum.reverse(list) ++ acc}}
        {:ok, {:spliced, _}} -> {:halt, {:error, Value.err(:E_TYPE)}}
        {:ok, val} -> {:cont, {:ok, [val | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, vals} -> {:ok, Enum.reverse(vals)}
      error -> error
    end
  end

  defp eval_binop(:+, {:num, a}, {:num, b}), do: {:ok, Value.num(a + b)}
  defp eval_binop(:-, {:num, a}, {:num, b}), do: {:ok, Value.num(a - b)}
  defp eval_binop(:*, {:num, a}, {:num, b}), do: {:ok, Value.num(a * b)}

  defp eval_binop(:/, {:num, _}, {:num, 0}), do: {:error, Value.err(:E_DIV)}
  defp eval_binop(:/, {:num, a}, {:num, b}), do: {:ok, Value.num(div(a, b))}

  defp eval_binop(:%, {:num, _}, {:num, 0}), do: {:error, Value.err(:E_DIV)}
  defp eval_binop(:%, {:num, a}, {:num, b}), do: {:ok, Value.num(rem(a, b))}

  defp eval_binop(:in, val, {:list, items}) do
    case Enum.any?(items, &Value.equal?(&1, val)) do
      true -> {:ok, Value.num(1)}
      false -> {:ok, Value.num(0)}
    end
  end

  defp eval_binop(:in, _val, _), do: {:error, Value.err(:E_TYPE)}

  defp eval_binop(:==, a, b) do
    case Value.equal?(a, b) do
      true -> {:ok, Value.num(1)}
      false -> {:ok, Value.num(0)}
    end
  end

  defp eval_binop(:!=, a, b) do
    case Value.equal?(a, b) do
      true -> {:ok, Value.num(0)}
      false -> {:ok, Value.num(1)}
    end
  end

  defp eval_binop(:<, {:num, a}, {:num, b}) do
    case a < b do
      true -> {:ok, Value.num(1)}
      false -> {:ok, Value.num(0)}
    end
  end

  defp eval_binop(:>, {:num, a}, {:num, b}) do
    case a > b do
      true -> {:ok, Value.num(1)}
      false -> {:ok, Value.num(0)}
    end
  end

  defp eval_binop(:<=, {:num, a}, {:num, b}) do
    case a <= b do
      true -> {:ok, Value.num(1)}
      false -> {:ok, Value.num(0)}
    end
  end

  defp eval_binop(:>=, {:num, a}, {:num, b}) do
    case a >= b do
      true -> {:ok, Value.num(1)}
      false -> {:ok, Value.num(0)}
    end
  end

  defp eval_binop(_op, _a, _b), do: {:error, Value.err(:E_TYPE)}

  defp eval_unop(:-, {:num, n}), do: {:ok, Value.num(-n)}

  defp eval_unop(:!, val) do
    case Value.truthy?(val) do
      true -> {:ok, Value.num(0)}
      false -> {:ok, Value.num(1)}
    end
  end

  defp eval_unop(:@, {:list, _} = val), do: {:ok, {:spliced, val}}
  defp eval_unop(:@, _), do: {:error, Value.err(:E_TYPE)}

  defp eval_unop(_op, _val), do: {:error, Value.err(:E_TYPE)}
end
