defmodule Alchemoo.Runtime do
  @moduledoc """
  Runtime environment for MOO execution.

  Manages object database access, property lookups, and verb calls.
  """

  alias Alchemoo.Database
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
  def call_verb(runtime, {:obj, obj_id}, verb_name, args, env) when is_binary(verb_name) do
    case Map.get(runtime.objects, obj_id) do
      nil -> {:error, Value.err(:E_INVIND)}
      object -> find_and_call_verb(object, verb_name, args, env, runtime)
    end
  end

  def call_verb(_runtime, _obj, _verb, _args, _env), do: {:error, Value.err(:E_TYPE)}

  # Find property in object or its parents
  defp find_property(object, prop_name, runtime) do
    case Enum.find(object.properties, &(&1.name == prop_name)) do
      nil ->
        lookup_parent_property(object.parent, prop_name, runtime)

      _prop ->
        # Return property value (for now, just return a placeholder)
        {:ok, Value.num(0)}
    end
  end

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
  defp find_and_call_verb(object, verb_name, args, env, runtime) do
    case Enum.find(object.verbs, &(&1.name == verb_name)) do
      nil ->
        lookup_parent_verb(object.parent, verb_name, args, env, runtime)

      verb ->
        # Execute verb code
        execute_verb(verb, args, env, runtime)
    end
  end

  defp lookup_parent_verb(parent_id, verb_name, args, env, runtime) when parent_id >= 0 do
    case Map.get(runtime.objects, parent_id) do
      nil -> {:error, Value.err(:E_VERBNF)}
      parent -> find_and_call_verb(parent, verb_name, args, env, runtime)
    end
  end

  defp lookup_parent_verb(_parent_id, _verb_name, _args, _env, _runtime) do
    {:error, Value.err(:E_VERBNF)}
  end

  # Execute verb code
  defp execute_verb(verb, args, env, runtime) do
    # Parse verb code
    case MOOSimple.parse(verb.code) do
      {:ok, %Alchemoo.AST.Block{statements: stmts}} ->
        # Set up verb environment
        verb_env =
          env
          |> Map.put(:runtime, runtime)
          |> Map.put("args", Value.list(args))

        # Execute statements
        try do
          _final_env =
            Enum.reduce(stmts, verb_env, fn stmt, current_env ->
              case Alchemoo.Interpreter.eval(stmt, current_env) do
                {:ok, _, new_env} -> new_env
                {:ok, _val} -> current_env
                {:error, err} -> throw({:error, err})
              end
            end)

          # If we get here, no explicit return - return 0
          {:ok, Value.num(0)}
        catch
          {:return, val} -> {:ok, val}
          {:error, err} -> {:error, err}
        end

      {:error, _reason} ->
        {:error, Value.err(:E_VERBNF)}
    end
  end
end
