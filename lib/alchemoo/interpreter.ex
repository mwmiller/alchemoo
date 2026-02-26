defmodule Alchemoo.Interpreter do
  @moduledoc """
  Simple tree-walking interpreter for MOO expressions.
  """

  require Logger
  alias Alchemoo.AST
  alias Alchemoo.Value

  @doc """
  Evaluate a MOO expression AST with given environment.
  """
  def eval(ast, env \\ %{}) do
    consume_tick()
    # Logger.debug("Eval: #{inspect(ast)}")

    case do_eval(ast, env) do
      {:ok, val, new_env} ->
        # Logger.debug("Eval Result: #{Value.to_literal(val)}")
        {:ok, val, new_env}

      {:ok, val} ->
        # Logger.debug("Eval Result: #{Value.to_literal(val)}")
        {:ok, val, env}

      {:error, {:err, _} = err} ->
        Logger.debug("MOO Error: #{inspect(err)} in #{inspect(ast)}")
        {:error, err}

      {:error, _} = err ->
        err
    end
  rescue
    e ->
      Logger.error(
        "Interpreter Crash: #{inspect(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      {:error, {:interpreter_error, e, __STACKTRACE__}}
  end

  defp consume_tick do
    case Process.get(:ticks_remaining) do
      nil -> :ok
      n when n <= 0 -> throw(:quota_exceeded)
      n -> Process.put(:ticks_remaining, n - 1)
    end
  end

  # --- do_eval clauses (Grouped together) ---

  defp do_eval(%AST.Literal{value: val}, _env), do: {:ok, val}

  defp do_eval(%AST.Var{name: name}, env) do
    case Map.get(env, name) do
      nil -> {:error, Value.err(:E_VARNF)}
      val -> {:ok, val}
    end
  end

  defp do_eval(%AST.BinOp{op: op, left: left, right: right}, env) do
    case op do
      :&& -> eval_logical_and(left, right, env)
      :|| -> eval_logical_or(left, right, env)
      _ -> eval_standard_binop(op, left, right, env)
    end
  end

  defp do_eval(%AST.UnaryOp{op: op, expr: expr}, env) do
    with {:ok, val, new_env} <- eval(expr, env) do
      case eval_unop(op, val) do
        {:ok, result} -> {:ok, result, new_env}
        {:error, _} = err -> err
      end
    end
  end

  defp do_eval(%AST.ListExpr{elements: elements}, env) do
    results =
      Enum.reduce_while(elements, {:ok, [], env}, fn elem, {:ok, acc, current_env} ->
        case eval(elem, current_env) do
          {:ok, {:spliced, {:list, list_items}}, next_env} ->
            {:cont, {:ok, Enum.reverse(list_items) ++ acc, next_env}}

          {:ok, val, next_env} ->
            {:cont, {:ok, [val | acc], next_env}}

          {:error, _} = err ->
            {:halt, err}
        end
      end)

    case results do
      {:ok, vals, final_env} -> {:ok, Value.list(Enum.reverse(vals)), final_env}
      error -> error
    end
  end

  defp do_eval(%AST.Index{expr: expr, index: index}, env) do
    with {:ok, coll, env1} <- eval(expr, env) do
      with_dollar(env1, coll, &eval_index_with_dollar(index, coll, &1))
    end
  end

  defp do_eval(%AST.Range{expr: expr, start: start_expr, end: end_expr}, env) do
    with {:ok, coll, env1} <- eval(expr, env) do
      with_dollar(env1, coll, &eval_range_with_dollar(start_expr, end_expr, coll, &1))
    end
  end

  defp do_eval(%AST.Conditional{condition: cond, then_expr: then_e, else_expr: else_e}, env) do
    with {:ok, cond_val, env1} <- eval(cond, env) do
      case Value.truthy?(cond_val) do
        true -> eval(then_e, env1)
        false -> eval(else_e, env1)
      end
    end
  end

  defp do_eval(%AST.FuncCall{name: name, args: arg_exprs}, env) do
    # Logger.debug("Interpreter: calling builtin #{name}()")

    with {:ok, arg_vals, env1} <- eval_args(arg_exprs, env) do
      Alchemoo.Builtins.call(name, arg_vals, env1)
    end
  end

  defp do_eval(%AST.PropRef{obj: obj_expr, prop: prop_expr}, env) do
    with {:ok, obj_val, env1} <- eval(obj_expr, env),
         {:ok, prop_name, env2} <- resolve_dynamic_name(prop_expr, env1) do
      case Map.get(env2, :runtime) do
        nil -> {:error, Value.err(:E_PERM)}
        runtime -> Alchemoo.Runtime.get_property(runtime, obj_val, prop_name)
      end
    end
  end

  defp do_eval(%AST.VerbCall{obj: obj_expr, verb: verb_expr, args: arg_exprs}, env) do
    with {:ok, obj_val, env1} <- eval(obj_expr, env),
         {:ok, verb_name, env2} <- resolve_dynamic_name(verb_expr, env1),
         {:ok, arg_vals, env3} <- eval_args(arg_exprs, env2) do
      execute_verb_call(obj_val, verb_name, arg_vals, env3)
    end
  end

  defp do_eval(%AST.Block{statements: stmts}, env) do
    # Logger.debug("Interpreter: entering block with #{length(stmts)} statements")
    eval_block(stmts, env)
  end

  defp do_eval(
         %AST.If{condition: cond, then_block: then_b, elseif_blocks: elseifs, else_block: else_b},
         env
       ) do
    with {:ok, cond_val, env1} <- eval(cond, env) do
      case Value.truthy?(cond_val) do
        true -> eval(then_b, env1)
        false -> eval_elseifs(elseifs, else_b, env1)
      end
    end
  end

  defp do_eval(%AST.While{condition: cond, body: body}, env) do
    eval_while(cond, body, env)
  end

  defp do_eval(%AST.ForList{var: var, list: list_expr, body: body}, env) do
    with {:ok, {:list, items}, env1} <- eval(list_expr, env) do
      eval_for_list(var, items, body, env1)
    end
  end

  defp do_eval(
         %AST.For{
           var: var,
           range: %AST.Range{expr: nil, start: start_expr, end: end_expr},
           body: body
         },
         env
       ) do
    with {:ok, {:num, start_idx}, env1} <- eval(start_expr, env),
         {:ok, {:num, end_idx}, env2} <- eval(end_expr, env1) do
      items =
        if start_idx <= end_idx do
          Enum.map(start_idx..end_idx, &Value.num/1)
        else
          []
        end

      eval_for_list(var, items, body, env2)
    end
  end

  defp do_eval(%AST.For{var: var, range: range_expr, body: body}, env) do
    with {:ok, range, env1} <- eval(range_expr, env) do
      items =
        case range do
          {:list, items} -> items
          _ -> []
        end

      eval_for_list(var, items, body, env1)
    end
  end

  defp do_eval(%AST.Return{value: val_expr}, env) do
    with {:ok, val, _new_env} <- eval(val_expr, env) do
      throw({:return, val})
    end
  end

  defp do_eval(%AST.Break{}, _env), do: throw(:break)
  defp do_eval(%AST.Continue{}, _env), do: throw(:continue)

  defp do_eval(%AST.Assignment{target: target, value: val_expr}, env) do
    with {:ok, val, env1} <- eval(val_expr, env) do
      perform_assignment(target, val, env1)
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

  defp do_eval(%AST.Catch{expr: expr, codes: codes, default: default}, env) do
    case eval(expr, env) do
      {:ok, result, new_env} ->
        {:ok, result, new_env}

      {:error, err} ->
        handle_catch_error(err, codes, default, env)
    end
  end

  defp do_eval(%AST.ExprStmt{expr: expr}, env), do: eval(expr, env)

  # --- Helper functions ---

  defp resolve_dynamic_name(name, env) when is_binary(name), do: {:ok, name, env}

  defp resolve_dynamic_name(name_expr, env) do
    case eval(name_expr, env) do
      {:ok, {:str, name}, new_env} -> {:ok, name, new_env}
      {:ok, _, _} -> {:error, Value.err(:E_TYPE)}
      err -> err
    end
  end

  defp with_dollar(env, coll, fun) do
    dollar_val =
      case Value.length(coll) do
        {:num, _} = len -> len
        {:err, _} = err -> err
      end

    prior = Map.get(env, "$", :__missing__)
    env_with_dollar = Map.put(env, "$", dollar_val)

    case fun.(env_with_dollar) do
      {:ok, val, env_after} ->
        {:ok, val, restore_dollar(env_after, prior)}

      {:error, _} = err ->
        err
    end
  end

  defp restore_dollar(env, :__missing__), do: Map.delete(env, "$")
  defp restore_dollar(env, prior), do: Map.put(env, "$", prior)

  defp eval_index_with_dollar(index_expr, coll, env_with_dollar) do
    with {:ok, idx, env2} <- eval(index_expr, env_with_dollar) do
      case Value.index(coll, idx) do
        {:err, _} = err -> {:error, err}
        val -> {:ok, val, env2}
      end
    end
  end

  defp eval_range_with_dollar(start_expr, end_expr, coll, env_with_dollar) do
    with {:ok, {:num, start_idx}, env2} <- eval(start_expr, env_with_dollar),
         {:ok, {:num, end_idx}, env3} <- eval(end_expr, env2) do
      case Value.range(coll, start_idx, end_idx) do
        {:err, _} = err -> {:error, err}
        val -> {:ok, val, env3}
      end
    end
  end

  defp eval_logical_and(left, right, env) do
    with {:ok, left_val, env1} <- eval(left, env) do
      case Value.truthy?(left_val) do
        true -> eval(right, env1)
        false -> {:ok, left_val, env1}
      end
    end
  end

  defp eval_logical_or(left, right, env) do
    with {:ok, left_val, env1} <- eval(left, env) do
      case Value.truthy?(left_val) do
        true -> {:ok, left_val, env1}
        false -> eval(right, env1)
      end
    end
  end

  defp eval_standard_binop(op, left, right, env) do
    with {:ok, left_val, env1} <- eval(left, env),
         {:ok, right_val, env2} <- eval(right, env1) do
      case eval_binop(op, left_val, right_val) do
        {:ok, val} -> {:ok, val, env2}
        {:error, _} = err -> err
      end
    end
  end

  defp execute_verb_call(obj_val, verb_name, arg_vals, env) do
    # Logger.debug("Interpreter: calling verb #{Value.to_literal(obj_val)}:#{verb_name}()")

    case Map.get(env, :runtime) do
      nil ->
        {:error, Value.err(:E_PERM)}

      runtime ->
        dispatch_verb_call(runtime, obj_val, verb_name, arg_vals, env)
    end
  end

  defp dispatch_verb_call(runtime, obj_val, verb_name, arg_vals, env) do
    case Alchemoo.Runtime.call_verb(runtime, obj_val, verb_name, arg_vals, env) do
      {:ok, result, new_runtime} ->
        {:ok, result, Map.put(env, :runtime, new_runtime)}

      {:error, err} ->
        {:error, err}
    end
  end

  # Helper: perform assignment to various targets
  defp perform_assignment(%AST.Var{name: name}, val, env) do
    {:ok, val, Map.put(env, name, val)}
  end

  defp perform_assignment(%AST.PropRef{obj: obj_expr, prop: prop_expr}, val, env) do
    with {:ok, obj_val, env1} <- eval(obj_expr, env),
         {:ok, prop_name, env2} <- resolve_dynamic_name(prop_expr, env1) do
      perform_prop_assignment(obj_val, prop_name, val, env2)
    end
  end

  defp perform_assignment(%AST.Index{expr: target_expr, index: index_expr}, val, env) do
    with {:ok, coll, env1} <- eval(target_expr, env),
         {:ok, idx, env2} <- eval(index_expr, env1) do
      case Value.set_index(coll, idx, val) do
        {:err, _} = err -> {:error, err}
        new_coll -> perform_assignment(target_expr, new_coll, env2)
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

  defp destructure_list(
         [%AST.OptionalVar{name: name, default: default} | rest_targets],
         values,
         env
       ) do
    case values do
      [val | rest_values] ->
        # Have value, use it
        with {:ok, _, env} <- perform_assignment(%AST.Var{name: name}, val, env) do
          destructure_list(rest_targets, rest_values, env)
        end

      [] ->
        # No value, use default
        # Default to 0 if no default provided (MOO spec?)
        assign_optional_default(name, default, rest_targets, env)
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
      {:ok, val, new_env} ->
        case rest do
          [] -> {:ok, val, new_env}
          _ -> eval_block(rest, new_env)
        end

      {:error, _} = err ->
        err
    end
  end

  # Helper: evaluate elseif chains
  defp eval_elseifs([], nil, env), do: {:ok, Value.num(0), env}
  defp eval_elseifs([], else_block, env), do: eval(else_block, env)

  defp eval_elseifs([%AST.ElseIf{condition: cond, block: block} | rest], else_block, env) do
    with {:ok, cond_val, env1} <- eval(cond, env) do
      case Value.truthy?(cond_val) do
        true -> eval(block, env1)
        false -> eval_elseifs(rest, else_block, env1)
      end
    end
  end

  defp eval_while(cond, body, env) do
    case eval(cond, env) do
      {:ok, cond_val, env1} ->
        handle_while_loop(cond_val, cond, body, env1)

      {:error, _} = err ->
        err
    end
  end

  defp handle_while_loop(cond_val, cond, body, env) do
    case Value.truthy?(cond_val) do
      true -> execute_while_body(cond, body, env)
      false -> {:ok, Value.num(0), env}
    end
  end

  defp execute_while_body(cond, body, env) do
    case catch_loop_control(fn -> eval(body, env) end) do
      {:break, env1} -> {:ok, Value.num(0), env1 || env}
      {:continue, env1} -> eval_while(cond, body, env1 || env)
      {:ok, _val, env1} -> eval_while(cond, body, env1)
      {:error, _} = err -> err
    end
  end

  # Helper: for-in loop
  defp eval_for_list(_var, [], _body, env), do: {:ok, Value.num(0), env}

  defp eval_for_list(var, [item | rest], body, env) do
    loop_env = Map.put(env, var, item)

    case catch_loop_control(fn -> eval(body, loop_env) end) do
      {:break, env1} -> {:ok, Value.num(0), env1 || env}
      {:continue, env1} -> eval_for_list(var, rest, body, env1 || env)
      {:ok, _val, env1} -> eval_for_list(var, rest, body, env1)
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
    Enum.reduce_while(arg_exprs, {:ok, [], env}, fn expr, {:ok, acc, current_env} ->
      case eval(expr, current_env) do
        {:ok, {:spliced, {:list, list}}, next_env} ->
          {:cont, {:ok, Enum.reverse(list) ++ acc, next_env}}

        {:ok, {:spliced, _}, _} ->
          {:halt, {:error, Value.err(:E_TYPE)}}

        {:ok, val, next_env} ->
          {:cont, {:ok, [val | acc], next_env}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> case do
      {:ok, vals, final_env} -> {:ok, Enum.reverse(vals), final_env}
      error -> error
    end
  end

  defp should_catch?(_err, :ANY, _env), do: true
  defp should_catch?(_err, nil, _env), do: true

  defp should_catch?(err, codes_expr, env) do
    case eval(codes_expr, env) do
      {:ok, {:list, items}, _} ->
        Enum.any?(items, &Value.equal?(&1, err))

      {:ok, item, _} ->
        Value.equal?(item, err)

      _ ->
        false
    end
  end

  defp handle_catch_error(err, codes, default, env) do
    if should_catch?(err, codes, env) do
      catch_default_result(default, err, env)
    else
      {:error, err}
    end
  end

  defp catch_default_result(nil, err, env), do: {:ok, err, env}
  defp catch_default_result(default, _err, env), do: eval(default, env)

  defp assign_optional_default(name, default, rest_targets, env) do
    default_val_expr = default || %AST.Literal{value: {:num, 0}}

    with {:ok, val, env} <- eval(default_val_expr, env),
         {:ok, _, env} <- perform_assignment(%AST.Var{name: name}, val, env) do
      destructure_list(rest_targets, [], env)
    end
  end

  defp eval_binop(:+, {:num, a}, {:num, b}), do: {:ok, Value.num(a + b)}
  defp eval_binop(:+, {:str, a}, {:str, b}), do: {:ok, Value.str(a <> b)}
  defp eval_binop(:+, {:str, a}, b), do: {:ok, Value.str(a <> Value.to_literal(b))}
  defp eval_binop(:+, a, {:str, b}), do: {:ok, Value.str(Value.to_literal(a) <> b)}
  defp eval_binop(:-, {:num, a}, {:num, b}), do: {:ok, Value.num(a - b)}
  defp eval_binop(:*, {:num, a}, {:num, b}), do: {:ok, Value.num(a * b)}

  defp eval_binop(:/, {:num, _}, {:num, 0}), do: {:error, Value.err(:E_DIV)}
  defp eval_binop(:/, {:num, a}, {:num, b}), do: {:ok, Value.num(div(a, b))}

  defp eval_binop(:%, {:num, _}, {:num, 0}), do: {:error, Value.err(:E_DIV)}
  defp eval_binop(:%, {:num, a}, {:num, b}), do: {:ok, Value.num(rem(a, b))}

  defp eval_binop(:^, {:num, a}, {:num, b}) when b >= 0 do
    {:ok, Value.num(round(:math.pow(a, b)))}
  end

  defp eval_binop(:^, {:num, a}, {:float, b}), do: {:ok, {:float, :math.pow(a, b)}}
  defp eval_binop(:^, {:float, a}, {:num, b}), do: {:ok, {:float, :math.pow(a, b)}}
  defp eval_binop(:^, {:float, a}, {:float, b}), do: {:ok, {:float, :math.pow(a, b)}}

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

  defp eval_binop(:<, {:str, a}, {:str, b}) do
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

  defp eval_binop(:>, {:str, a}, {:str, b}) do
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

  defp eval_binop(:<=, {:str, a}, {:str, b}) do
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

  defp eval_binop(:>=, {:str, a}, {:str, b}) do
    case a >= b do
      true -> {:ok, Value.num(1)}
      false -> {:ok, Value.num(0)}
    end
  end

  defp eval_binop(_op, _a, _b), do: {:error, Value.err(:E_TYPE)}

  defp eval_unop(:-, {:num, n}), do: {:ok, Value.num(-n)}
  defp eval_unop(:-, {:float, n}), do: {:ok, {:float, -n}}

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
