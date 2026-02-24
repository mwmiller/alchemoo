defmodule Alchemoo.Runtime do
  @moduledoc """
  Runtime environment for MOO execution.

  Manages object database access, property lookups, and verb calls.
  """
  require Logger

  alias Alchemoo.Database
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
    case Map.get(runtime.objects, obj_id) do
      nil -> {:error, Value.err(:E_INVIND)}
      object -> find_property(object, prop_name, runtime)
    end
  end

  def get_property(_runtime, _obj, _prop), do: {:error, Value.err(:E_TYPE)}

  @doc """
  Set property value on an object.
  """
  def set_property(runtime, {:obj, obj_id}, prop_name, value) when is_binary(prop_name) do
    case Map.get(runtime.objects, obj_id) do
      nil ->
        {:error, Value.err(:E_INVIND)}

      _object ->
        # For now, just return success - full implementation would update the object
        {:ok, value, runtime}
    end
  end

  def set_property(_runtime, _obj, _prop, _value), do: {:error, Value.err(:E_TYPE)}

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

    case Map.get(runtime.objects, obj_id) do
      nil -> {:error, Value.err(:E_INVIND)}
      object -> find_and_call_verb(object, verb_name, args, env, runtime, actual_receiver)
    end
  end

  def call_verb(_runtime, _obj, _verb, _args, _env, _receiver), do: {:error, Value.err(:E_TYPE)}

  # Find property in object or its parents
  defp find_property(object, prop_name, runtime) do
    case lookup_builtin_property(object, prop_name) do
      {:ok, _} = result ->
        result

      :not_builtin ->
        # Check local properties first
        case Enum.find(object.properties, &(&1.name == prop_name)) do
          %Alchemoo.Database.Property{value: :clear} ->
            lookup_parent_property(object.parent, prop_name, runtime)

          prop when not is_nil(prop) ->
            {:ok, prop.value}

          nil ->
            # Check overridden inherited properties
            case Map.get(object.overridden_properties, prop_name) do
              nil -> lookup_parent_property(object.parent, prop_name, runtime)
              prop -> {:ok, prop.value}
            end
        end
    end
  end

  defp lookup_builtin_property(object, "name"), do: {:ok, {:str, object.name}}
  defp lookup_builtin_property(object, "owner"), do: {:ok, {:obj, object.owner}}
  defp lookup_builtin_property(object, "location"), do: {:ok, {:obj, object.location}}

  defp lookup_builtin_property(object, "contents"),
    do: {:ok, {:list, Enum.map(object.contents, &Value.obj/1)}}

  defp lookup_builtin_property(object, "parent"), do: {:ok, {:obj, object.parent}}
  defp lookup_builtin_property(_object, _prop_name), do: :not_builtin

  defp lookup_parent_property(parent_id, prop_name, runtime) when parent_id >= 0 do
    case Map.get(runtime.objects, parent_id) do
      nil -> {:error, Value.err(:E_PROPNF)}
      parent -> find_property(parent, prop_name, runtime)
    end
  end

  defp lookup_parent_property(_parent_id, _prop_name, _runtime) do
    {:error, Value.err(:E_PROPNF)}
  end

  # Find and call verb in object or its parents
  defp find_and_call_verb(object, verb_name, args, env, runtime, receiver_id) do
    case Enum.find(object.verbs, fn v -> Verb.match?(v, verb_name) end) do
      nil ->
        lookup_parent_verb(object.parent, verb_name, args, env, runtime, receiver_id)

      verb ->
        # Execute verb code - passing object.id as definer and original receiver as this
        execute_verb(receiver_id, object.id, verb, args, env, runtime)
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
  defp execute_verb(this_id, definer_id, verb, args, env, runtime) do
    # Save current task context for restoration
    old_context = Process.get(:task_context)

    # Create new task context for this verb call
    new_context = build_new_context(old_context, this_id, definer_id, verb)

    Process.put(:task_context, new_context)

    # Parse verb code
    try do
      perform_verb_execution(verb, this_id, args, env, runtime, new_context)
    after
      # Restore old context
      Process.put(:task_context, old_context)
    end
  end

  defp build_new_context(nil, this_id, definer_id, verb) do
    # Default context for testing or initial calls
    %{
      this: this_id,
      player: 2,
      caller: -1,
      perms: 2,
      caller_perms: 0,
      verb_definer: definer_id,
      verb_name: verb.name,
      stack: []
    }
  end

  defp build_new_context(context, this_id, definer_id, verb) do
    %{
      context
      | this: this_id,
        caller: context[:this] || -1,
        caller_perms: context[:perms] || 0,
        verb_definer: definer_id,
        verb_name: verb.name,
        # MOO manual says verbs start with their owner's perms
        perms: verb.owner,
        stack: [
          %{
            this: context[:this] || -1,
            verb_name: context[:verb_name] || "(initial)",
            verb_owner: context[:perms] || 0,
            player: context[:player] || 2
          }
          | context[:stack] || []
        ]
    }
  end

  defp perform_verb_execution(verb, this_id, args, env, runtime, context) do
    definer_id = context[:verb_definer] || this_id

    # Check for cached AST
    case verb.ast do
      %Alchemoo.AST.Block{statements: stmts} ->
        Logger.debug("Runtime: executing cached AST for #{Alchemoo.Value.to_literal(Value.obj(this_id))}:#{verb.name}()")
        verb_env = build_verb_env(env, runtime, args, this_id, verb.name, context)

        case execute_statements(stmts, verb_env) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            # If execution fails, invalidate the cache just in case the AST is problematic
            Logger.info("Runtime: verb execution failed for ##{this_id}:#{verb.name}, invalidating AST cache")
            Alchemoo.Database.Server.set_verb_ast(definer_id, verb.name, nil)
            {:error, reason}
        end

      nil ->
        Logger.debug("Runtime: parsing verb code for #{Alchemoo.Value.to_literal(Value.obj(this_id))}:#{verb.name}()")

        case MOOSimple.parse(verb.code) do
          {:ok, %Alchemoo.AST.Block{statements: stmts} = ast} ->
            # Cache AST in server for future calls
            Alchemoo.Database.Server.set_verb_ast(definer_id, verb.name, ast)

            verb_env = build_verb_env(env, runtime, args, this_id, verb.name, context)
            execute_statements(stmts, verb_env)

          {:error, reason} ->
            Logger.error("Runtime: failed to parse verb code for ##{this_id}:#{verb.name}: #{inspect(reason)}")
            {:error, Value.err(:E_VERBNF)}
        end
    end
  end

  defp build_verb_env(env, runtime, args, this_id, verb_name, context) do
    %{
      :runtime => runtime,
      "args" => Value.list(args),
      "this" => Value.obj(this_id),
      "player" => Value.obj(context[:player] || 2),
      "caller" => Value.obj(context[:caller] || -1),
      "verb" => Value.str(verb_name),
      # Inherit command variables from caller's env
      "argstr" => Map.get(env, "argstr", Value.str("")),
      "dobj" => Map.get(env, "dobj", Value.obj(-1)),
      "dobjstr" => Map.get(env, "dobjstr", Value.str("")),
      "prepstr" => Map.get(env, "prepstr", Value.str("")),
      "iobj" => Map.get(env, "iobj", Value.obj(-1)),
      "iobjstr" => Map.get(env, "iobjstr", Value.str(""))
    }
  end

  defp execute_statements(stmts, env) do
    _final_env =
      Enum.reduce(stmts, env, fn stmt, current_env ->
        case Alchemoo.Interpreter.eval(stmt, current_env) do
          {:ok, _, new_env} -> new_env
          {:ok, _val} -> current_env
          {:error, err} -> throw({:error, err})
        end
      end)

    # If we get here, no explicit return - return 0
    {:ok, Value.num(0)}
  rescue
    e -> {:error, e}
  catch
    {:return, val} -> {:ok, val}
    {:error, err} -> {:error, err}
  end
end
