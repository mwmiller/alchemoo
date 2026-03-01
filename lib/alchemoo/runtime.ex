defmodule Alchemoo.Runtime do
  @moduledoc """
  Runtime environment for MOO execution.

  Manages object database access, property lookups, and verb calls.
  """
  require Logger

  alias Alchemoo.Database
  alias Alchemoo.Database.Flags
  alias Alchemoo.Database.Permissions
  alias Alchemoo.Database.Server, as: DB
  alias Alchemoo.Database.Verb
  alias Alchemoo.Parser.MOOSimple
  alias Alchemoo.Value

  defstruct [:db, :objects]

  @doc """
  Create a new runtime from a parsed database.
  """
  def new(%Database{} = db) do
    %__MODULE__{
      db: db,
      objects: db.objects
    }
  end

  @doc """
  Get property value from an object.
  """
  def get_property(runtime, {:obj, obj_id}, prop_name) when is_binary(prop_name) do
    with {:ok, object} <- lookup_object(runtime, obj_id),
         {:ok, val, info} <- find_property_with_info(object, prop_name, runtime) do
      check_read_permission(val, info, obj_id, prop_name)
    else
      {:error, err} ->
        maybe_log_property_lookup("##{obj_id}.#{prop_name}", "ERROR: #{inspect(err)}")
        {:error, err}
    end
  end

  def get_property(_runtime, _obj, _prop), do: {:error, Value.err(:E_TYPE)}

  defp lookup_object(runtime, obj_id) do
    case Map.get(runtime.objects, obj_id) do
      nil -> {:error, Value.err(:E_INVIND)}
      object -> {:ok, object}
    end
  end

  defp check_read_permission(val, info, obj_id, prop_name) do
    player_id = get_current_player()

    if Permissions.property_allows?(info, player_id, Permissions.read()) do
      maybe_log_property_lookup("##{obj_id}.#{prop_name}", Value.to_literal(val))
      {:ok, val}
    else
      maybe_log_property_lookup("##{obj_id}.#{prop_name}", "E_PERM")
      {:error, Value.err(:E_PERM)}
    end
  end

  @doc """
  Set property value on an object.
  """
  def set_property(runtime, {:obj, obj_id}, prop_name, value) when is_binary(prop_name) do
    with {:ok, object} <- lookup_object(runtime, obj_id),
         {:ok, info} <- find_property_info(object, prop_name, runtime) do
      if Permissions.property_allows?(info, get_current_player(), Permissions.write()) do
        perform_set_property(runtime, object, obj_id, prop_name, value, info)
      else
        {:error, Value.err(:E_PERM)}
      end
    end
  end

  def set_property(_runtime, _obj, _prop, _value), do: {:error, Value.err(:E_TYPE)}

  defp perform_set_property(runtime, object, obj_id, prop_name, value, info) do
    search_name = String.downcase(prop_name)

    case Enum.find_index(object.properties, &(String.downcase(&1.name) == search_name)) do
      idx when is_integer(idx) ->
        # Update local property
        new_properties = List.update_at(object.properties, idx, &%{&1 | value: value})
        new_object = %{object | properties: new_properties}
        new_objects = Map.put(runtime.objects, obj_id, new_object)
        {:ok, value, %{runtime | objects: new_objects}}

      nil ->
        # Check inherited property and override it
        # Inherit perms/owner from the parent property definition
        new_prop = %Alchemoo.Database.Property{
          name: prop_name,
          value: value,
          owner: info.owner,
          perms: info.perms
        }

        new_overridden = Map.put(object.overridden_properties, prop_name, new_prop)
        new_object = %{object | overridden_properties: new_overridden}
        new_objects = Map.put(runtime.objects, obj_id, new_object)
        {:ok, value, %{runtime | objects: new_objects}}
    end
  end

  @doc """
  Call a verb on an object.
  """
  def call_verb(runtime, obj, verb_name, args, env) do
    call_verb(runtime, obj, verb_name, args, env, nil)
  end

  @doc """
  Call a verb on an object with an explicit receiver (this).
  """
  def call_verb(runtime, {:obj, obj_id}, verb_name, args, env, receiver_id)
      when is_binary(verb_name) do
    # Default receiver to obj_id if not provided
    actual_receiver = receiver_id || obj_id

    # If we don't have a task context (e.g. initial call from Elixir or test),
    # we should set one up so permissions work.
    # We'll use #2 (Wizard) as the default caller for these top-level entries.
    old_context = Process.get(:task_context)

    if is_nil(old_context) do
      Process.put(:task_context, %{
        this: actual_receiver,
        player: 2,
        caller: -1,
        perms: 2,
        caller_perms: 2,
        verb_definer: obj_id,
        verb_name: verb_name,
        stack: []
      })
    end

    try do
      case Map.get(runtime.objects, obj_id) do
        nil ->
          if obj_id < 0 and verb_name == "tell" do
            # Special case for tell on negative IDs (un-logged-in connections)
            Alchemoo.Builtins.notify([
              Value.obj(obj_id),
              Value.str(Enum.map_join(args, &Value.to_literal/1))
            ])

            {:ok, Value.num(1), runtime}
          else
            {:error, Value.err(:E_INVIND)}
          end

        object ->
          find_and_call_verb(object, verb_name, args, env, runtime, actual_receiver)
      end
    after
      if is_nil(old_context), do: Process.delete(:task_context)
    end
  end

  def call_verb(_runtime, _obj, _verb, _args, _env, _receiver), do: {:error, Value.err(:E_TYPE)}

  defp get_current_player do
    case Process.get(:task_context) do
      nil -> -1
      ctx -> ctx[:perms] || -1
    end
  end

  # Find property in object or its parents, returning both value and the property struct (for info)
  defp find_property_with_info(object, prop_name, runtime) do
    case lookup_builtin_property(object, prop_name) do
      {:ok, _} = result ->
        # Built-in properties are always readable, and they don't have a Property struct.
        # We'll return a dummy property info that allows anything.
        {:ok, elem(result, 1), %{owner: 0, perms: 0xFFFF}}

      :not_builtin ->
        find_non_builtin_property_with_info(object, prop_name, runtime)
    end
  end

  defp find_non_builtin_property_with_info(object, prop_name, runtime) do
    # Check local properties first
    search_name = String.downcase(prop_name)

    case Enum.find(object.properties, &(String.downcase(&1.name) == search_name)) do
      %Alchemoo.Database.Property{value: :clear} = prop ->
        case lookup_parent_property_with_info(object.parent, prop_name, runtime) do
          {:ok, val, _parent_info} -> {:ok, val, prop}
          err -> err
        end

      prop when not is_nil(prop) ->
        {:ok, prop.value, prop}

      nil ->
        find_overridden_property_with_info(object, search_name, runtime)
    end
  end

  defp find_overridden_property_with_info(object, search_name, runtime) do
    # Check overridden inherited properties
    case Enum.find(object.overridden_properties, fn {k, _v} ->
           String.downcase(k) == search_name
         end) do
      nil ->
        lookup_parent_property_with_info(object.parent, search_name, runtime)

      {_k, %Alchemoo.Database.Property{value: :clear} = prop} ->
        case lookup_parent_property_with_info(object.parent, search_name, runtime) do
          {:ok, val, _parent_info} -> {:ok, val, prop}
          err -> err
        end

      {_k, prop} ->
        {:ok, prop.value, prop}
    end
  end

  defp find_property_info(object, prop_name, runtime) do
    case find_property_with_info(object, prop_name, runtime) do
      {:ok, _val, info} -> {:ok, info}
      err -> err
    end
  end

  defp lookup_builtin_property(object, prop_name) do
    case String.downcase(prop_name) do
      "name" -> {:ok, {:str, object.name}}
      "owner" -> {:ok, {:obj, object.owner}}
      "location" -> {:ok, {:obj, object.location}}
      "contents" -> {:ok, {:list, Enum.map(object.contents, &Value.obj/1)}}
      "parent" -> {:ok, {:obj, object.parent}}
      _ -> lookup_builtin_flags(object, prop_name)
    end
  end

  defp lookup_builtin_flags(object, prop_name) do
    case String.downcase(prop_name) do
      "wizard" ->
        {:ok, Value.num(if Flags.set?(object.flags, Flags.wizard()), do: 1, else: 0)}

      "programmer" ->
        {:ok, Value.num(if Flags.set?(object.flags, Flags.programmer()), do: 1, else: 0)}

      _ ->
        :not_builtin
    end
  end

  defp lookup_parent_property_with_info(parent_id, prop_name, runtime) when parent_id >= 0 do
    case Map.get(runtime.objects, parent_id) do
      nil -> {:error, Value.err(:E_PROPNF)}
      parent -> find_property_with_info(parent, prop_name, runtime)
    end
  end

  defp lookup_parent_property_with_info(_parent_id, _prop_name, _runtime) do
    {:error, Value.err(:E_PROPNF)}
  end

  # Find and call verb in object or its parents
  defp find_and_call_verb(object, verb_name, args, env, runtime, receiver_id) do
    case Enum.find(object.verbs, fn v ->
           Verb.match?(v, verb_name) and
             Permissions.verb_allows?(v, get_current_player(), Permissions.exec())
         end) do
      nil ->
        lookup_parent_verb(object.parent, verb_name, args, env, runtime, receiver_id)

      verb ->
        # Execute verb code - passing object.id as definer and original receiver as this
        # Pass verb_name as the invoked name
        execute_verb(receiver_id, object.id, verb, verb_name, args, env, runtime)
    end
  end

  defp lookup_parent_verb(parent_id, verb_name, args, env, runtime, receiver_id)
       when parent_id >= 0 do
    case Map.get(runtime.objects, parent_id) do
      nil -> {:error, Value.err(:E_VERBNF)}
      parent -> find_and_call_verb(parent, verb_name, args, env, runtime, receiver_id)
    end
  end

  defp lookup_parent_verb(_parent_id, _verb_name, _args, _env, _runtime, _receiver_id) do
    {:error, Value.err(:E_VERBNF)}
  end

  # Execute verb code
  defp execute_verb(this_id, definer_id, verb, invoked_name, args, env, runtime) do
    # Save current task context for restoration
    old_context = Process.get(:task_context)

    # Create new task context for this verb call
    new_context = build_new_context(old_context, this_id, definer_id, verb, invoked_name)

    Process.put(:task_context, new_context)

    # Parse verb code
    try do
      perform_verb_execution(verb, this_id, args, env, runtime, new_context)
    after
      # Restore old context
      Process.put(:task_context, old_context)
    end
  end

  defp build_new_context(nil, this_id, definer_id, _verb, invoked_name) do
    # Default context for testing or initial calls
    %{
      this: this_id,
      player: -1,
      caller: -1,
      perms: -1,
      caller_perms: -1,
      verb_definer: definer_id,
      verb_name: invoked_name,
      stack: []
    }
  end

  defp build_new_context(context, this_id, definer_id, verb, invoked_name) do
    # MOO logic for verb permissions:
    # If the 'x' bit (VF_EXEC/setuid) is NOT set, the verb runs with the caller's permissions.
    # If the 'x' bit IS set, the verb runs with the owner's permissions.
    # VF_EXEC is bit 4 (0x04) in the permission mask.
    old_perms = Map.get(context, :perms, -1)

    new_perms =
      if Permissions.verb_allows?(verb, old_perms, Permissions.exec()) do
        verb.owner
      else
        old_perms
      end

    Map.merge(context, %{
      this: this_id,
      caller: Map.get(context, :this, -1),
      caller_perms: old_perms,
      verb_definer: definer_id,
      verb_name: invoked_name,
      perms: new_perms,
      stack: [
        %{
          this: Map.get(context, :this, -1),
          verb_name: Map.get(context, :verb_name, "(initial)"),
          verb_owner: old_perms,
          player: Map.get(context, :player, -1)
        }
        | Map.get(context, :stack, [])
      ]
    })
  end

  defp perform_verb_execution(verb, this_id, args, env, runtime, context) do
    case verb.ast do
      %Alchemoo.AST.Block{} = ast ->
        execute_cached_ast(ast, verb, this_id, args, env, runtime, context)

      nil ->
        parse_and_execute_verb(verb, this_id, args, env, runtime, context)
    end
  end

  defp execute_cached_ast(ast, verb, this_id, args, env, runtime, context) do
    if trace_runtime_verbs?() do
      Logger.debug(
        "Runtime: executing cached AST for #{Value.to_literal(Value.obj(this_id))}:#{verb.name}()"
      )
    end

    verb_env = build_verb_env(env, runtime, args, this_id, verb.name, context)

    case execute_statements(ast.statements, verb_env) do
      {:ok, result, final_env} ->
        {:ok, result, Map.get(final_env, :runtime, runtime)}

      {:error, reason, _final_env} ->
        handle_exec_failure(verb, this_id, reason, context)
    end
  end

  defp handle_exec_failure(verb, this_id, reason, context) do
    # If execution fails, invalidate the cache just in case the AST is problematic
    Logger.debug(
      "Runtime: verb execution failed for ##{this_id}:#{verb.name}, invalidating AST cache"
    )

    definer_id = context[:verb_definer] || this_id
    DB.set_verb_ast(definer_id, verb.name, nil)
    {:error, reason}
  end

  defp parse_and_execute_verb(verb, this_id, args, env, runtime, context) do
    if trace_runtime_verbs?() do
      Logger.debug(
        "Runtime: parsing verb code for #{Value.to_literal(Value.obj(this_id))}:#{verb.name}()"
      )
    end

    case MOOSimple.parse(verb.code) do
      {:ok, %Alchemoo.AST.Block{} = ast} ->
        definer_id = context[:verb_definer] || this_id
        DB.set_verb_ast(definer_id, verb.name, ast)
        execute_cached_ast(ast, verb, this_id, args, env, runtime, context)

      {:error, reason} ->
        Logger.error(
          "Runtime: failed to parse verb code for ##{this_id}:#{verb.name}: #{inspect(reason)}"
        )

        maybe_log_parse_failure_source(verb)

        {:error, Value.err(:E_VERBNF)}
    end
  end

  defp build_verb_env(env, runtime, args, this_id, _verb_name, context) do
    %{
      :runtime => runtime,
      "args" => Value.list(args),
      "this" => Value.obj(this_id),
      "player" => Value.obj(context[:player] || -1),
      "caller" => Value.obj(context[:caller] || -1),
      "verb" => Value.str(context[:verb_name]),
      # Standard MOO type constants
      "INT" => Value.num(0),
      "NUM" => Value.num(0),
      "OBJ" => Value.num(1),
      "STR" => Value.num(2),
      "ERR" => Value.num(3),
      "LIST" => Value.num(4),
      # Standard MOO error constants
      "E_NONE" => Value.err(:E_NONE),
      "E_TYPE" => Value.err(:E_TYPE),
      "E_DIV" => Value.err(:E_DIV),
      "E_PERM" => Value.err(:E_PERM),
      "E_PROPNF" => Value.err(:E_PROPNF),
      "E_VERBNF" => Value.err(:E_VERBNF),
      "E_VARNF" => Value.err(:E_VARNF),
      "E_INVIND" => Value.err(:E_INVIND),
      "E_RECMOVE" => Value.err(:E_RECMOVE),
      "E_MAXREC" => Value.err(:E_MAXREC),
      "E_RANGE" => Value.err(:E_RANGE),
      "E_ARGS" => Value.err(:E_ARGS),
      "E_NACC" => Value.err(:E_NACC),
      "E_INVARG" => Value.err(:E_INVARG),
      "E_QUOTA" => Value.err(:E_QUOTA),
      "E_FLOAT" => Value.err(:E_FLOAT),
      # Inherit command variables from caller's env
      "argstr" => Map.get(env, "argstr", Value.str("")),
      "dobj" => Map.get(env, "dobj", Value.obj(-1)),
      "dobjstr" => Map.get(env, "dobjstr", Value.str("")),
      "prepstr" => Map.get(env, "prepstr", Value.str("")),
      "iobj" => Map.get(env, "iobj", Value.obj(-1)),
      "iobjstr" => Map.get(env, "iobjstr", Value.str(""))
    }
  end

  defp maybe_log_property_lookup(prop_ref, result) do
    if trace_runtime_properties?() do
      Logger.debug("Property Lookup: #{prop_ref} -> #{result}")
    end
  end

  defp trace_runtime_verbs?, do: Application.get_env(:alchemoo, :trace_runtime_verbs, false)

  defp trace_runtime_properties?,
    do: Application.get_env(:alchemoo, :trace_runtime_properties, false)

  defp maybe_log_parse_failure_source(verb) do
    if Application.get_env(:alchemoo, :trace_runtime_verbs, false) do
      snippet =
        verb.code
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {line, idx} -> "#{idx}: #{line}" end)

      Logger.debug("Runtime parse source for #{verb.name}:\n" <> snippet)
    end
  end

  defp execute_statements(stmts, env) do
    # Use Alchemoo.Interpreter.eval_block since it now handles env propagation
    Alchemoo.Interpreter.eval(%Alchemoo.AST.Block{statements: stmts}, env)
  rescue
    e ->
      Logger.error("Runtime: execution exception: #{inspect(e)}")
      {:error, e, env}
  catch
    {:return, val} ->
      {:ok, val, env}

    {:error, err, new_env} ->
      {:error, err, new_env}

    {:error, err} ->
      {:error, err, env}
  end
end
