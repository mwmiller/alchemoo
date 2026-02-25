defmodule Alchemoo.Database.Server do
  @moduledoc """
  GenServer that holds the in-memory MOO database and handles updates.
  """
  use GenServer
  require Logger

  alias Alchemoo.Database
  alias Alchemoo.Database.Flags
  alias Alchemoo.Database.Object
  alias Alchemoo.Database.Property
  alias Alchemoo.Database.Verb

  defstruct [:db, :db_path]

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_snapshot do
    GenServer.call(__MODULE__, :get_snapshot)
  end

  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  def load(path) do
    GenServer.call(__MODULE__, {:load, path}, :infinity)
  end

  def get_object(id) do
    GenServer.call(__MODULE__, {:get_object, id})
  end

  def find_verb(obj_id, verb_name) do
    GenServer.call(__MODULE__, {:find_verb, obj_id, verb_name})
  end

  def get_property(obj_id, prop_name) do
    GenServer.call(__MODULE__, {:get_property, obj_id, prop_name})
  end

  def set_property(obj_id, prop_name, value) do
    GenServer.call(__MODULE__, {:set_property, obj_id, prop_name, value})
  end

  def get_property_info(obj_id, prop_name) do
    GenServer.call(__MODULE__, {:get_property_info, obj_id, prop_name})
  end

  def set_property_info(obj_id, prop_name, info) do
    GenServer.call(__MODULE__, {:set_property_info, obj_id, prop_name, info})
  end

  def clear_property?(obj_id, prop_name) do
    GenServer.call(__MODULE__, {:is_clear_property, obj_id, prop_name})
  end

  def get_verb_info(obj_id, verb_name) do
    GenServer.call(__MODULE__, {:get_verb_info, obj_id, verb_name})
  end

  def set_verb_info(obj_id, verb_name, info) do
    GenServer.call(__MODULE__, {:set_verb_info, obj_id, verb_name, info})
  end

  def get_verb_args(obj_id, verb_name) do
    GenServer.call(__MODULE__, {:get_verb_args, obj_id, verb_name})
  end

  def set_verb_args(obj_id, verb_name, args) do
    GenServer.call(__MODULE__, {:set_verb_args, obj_id, verb_name, args})
  end

  def set_verb_code(obj_id, verb_name, code) do
    GenServer.call(__MODULE__, {:set_verb_code, obj_id, verb_name, code})
  end

  def set_verb_ast(obj_id, verb_name, ast) do
    GenServer.cast(__MODULE__, {:set_verb_ast, obj_id, verb_name, ast})
  end

  def add_verb(obj_id, name, owner, perms, args) do
    GenServer.call(__MODULE__, {:add_verb, obj_id, name, owner, perms, args})
  end

  def delete_verb(obj_id, verb_name) do
    GenServer.call(__MODULE__, {:delete_verb, obj_id, verb_name})
  end

  def add_property(obj_id, name, value, owner, perms) do
    GenServer.call(__MODULE__, {:add_property, obj_id, name, value, owner, perms})
  end

  def delete_property(obj_id, name) do
    GenServer.call(__MODULE__, {:delete_property, obj_id, name})
  end

  def create_object(parent_id, owner_id \\ 2) do
    GenServer.call(__MODULE__, {:create_object, parent_id, owner_id})
  end

  def recycle_object(obj_id) do
    GenServer.call(__MODULE__, {:recycle_object, obj_id})
  end

  def change_parent(obj_id, parent_id) do
    GenServer.call(__MODULE__, {:change_parent, obj_id, parent_id})
  end

  def move_object(obj_id, dest_id) do
    GenServer.call(__MODULE__, {:move_object, obj_id, dest_id})
  end

  def set_player_flag(obj_id, value) do
    GenServer.call(__MODULE__, {:set_player_flag, obj_id, value})
  end

  def chown_object(obj_id, owner_id) do
    GenServer.call(__MODULE__, {:chown_object, obj_id, owner_id})
  end

  def renumber_object(obj_id) do
    GenServer.call(__MODULE__, {:renumber_object, obj_id})
  end

  def reset_max_object do
    GenServer.call(__MODULE__, :reset_max_object)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Check for core database if no path provided
    db_path =
      case Keyword.get(opts, :core_db) do
        nil -> Application.get_env(:alchemoo, :core_db)
        opt_db -> opt_db
      end

    db =
      case db_path && File.read(db_path) do
        {:ok, content} ->
          Logger.info("Loading database from #{db_path}")

          case Database.Parser.parse(content) do
            {:ok, db} -> db
            _ -> %Database{}
          end

        _ ->
          Logger.info("Starting with empty database")
          %Database{}
      end

    {:ok, %__MODULE__{db: db, db_path: db_path}}
  end

  @impl true
  def handle_call(:get_snapshot, _from, state) do
    {:reply, state.db, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      object_count: map_size(state.db.objects),
      max_object: state.db.max_object,
      db_path: state.db_path,
      loaded: !is_nil(state.db_path)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:load, path}, _from, state) do
    case File.read(path) do
      {:ok, content} ->
        case Database.Parser.parse(content) do
          {:ok, db} ->
            {:reply, {:ok, map_size(db.objects)}, %{state | db: db, db_path: path}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_object, id}, _from, state) do
    case Map.get(state.db.objects, id) do
      nil -> {:reply, {:error, :E_INVIND}, state}
      obj -> {:reply, {:ok, obj}, state}
    end
  end

  @impl true
  def handle_call({:find_verb, obj_id, verb_name}, _from, state) do
    case find_verb_recursive(state.db.objects, obj_id, verb_name) do
      {:ok, definer_id, verb} -> {:reply, {:ok, definer_id, verb}, state}
      nil -> {:reply, {:error, :E_VERBNF}, state}
    end
  end

  @impl true
  def handle_call({:get_property, obj_id, prop_name}, _from, state) do
    case Map.has_key?(state.db.objects, obj_id) do
      false ->
        {:reply, {:error, :E_INVIND}, state}

      true ->
        case find_property_recursive(state.db.objects, obj_id, prop_name) do
          {:ok, value} -> {:reply, {:ok, value}, state}
          nil -> {:reply, {:error, :E_PROPNF}, state}
        end
    end
  end

  @impl true
  def handle_call({:set_property, obj_id, prop_name, value}, _from, state) do
    case perform_set_property(state, obj_id, prop_name, value) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end

  @impl true
  def handle_call({:get_property_info, obj_id, prop_name}, _from, state) do
    res =
      with {:ok, obj} <- get_obj(state, obj_id),
           {:ok, prop} <- find_prop(obj, prop_name) do
        {:ok, {prop.owner, prop.perms}}
      end

    {:reply, res, state}
  end

  @impl true
  def handle_call({:set_property_info, obj_id, prop_name, info}, _from, state) do
    case perform_set_property_info(state, obj_id, prop_name, info) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end

  @impl true
  def handle_call({:is_clear_property, obj_id, prop_name}, _from, state) do
    res =
      with {:ok, obj} <- get_obj(state, obj_id),
           {:ok, prop} <- find_prop(obj, prop_name) do
        {:ok, prop.value == :clear}
      end

    {:reply, res, state}
  end

  @impl true
  def handle_call({:get_verb_info, obj_id, verb_name}, _from, state) do
    res =
      with {:ok, obj} <- get_obj(state, obj_id),
           {:ok, verb} <- find_verb_local(obj, verb_name) do
        {:ok, {verb.owner, verb.perms, verb.name}}
      end

    {:reply, res, state}
  end

  @impl true
  def handle_call({:set_verb_info, obj_id, verb_name, info}, _from, state) do
    case perform_set_verb_info(state, obj_id, verb_name, info) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end

  @impl true
  def handle_call({:get_verb_args, obj_id, verb_name}, _from, state) do
    res =
      with {:ok, obj} <- get_obj(state, obj_id),
           {:ok, verb} <- find_verb_local(obj, verb_name) do
        {:ok, verb.args}
      end

    {:reply, res, state}
  end

  @impl true
  def handle_call({:set_verb_args, obj_id, verb_name, args}, _from, state) do
    case perform_set_verb_args(state, obj_id, verb_name, args) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end

  @impl true
  def handle_call({:set_verb_code, obj_id, verb_name, code}, _from, state) do
    case perform_set_verb_code(state, obj_id, verb_name, code) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end

  @impl true
  def handle_call({:add_verb, obj_id, name, owner, perms, args}, _from, state) do
    case Map.get(state.db.objects, obj_id) do
      nil ->
        {:reply, {:error, :E_INVIND}, state}

      obj ->
        new_verb = %Verb{
          name: name,
          owner: owner,
          perms: perms,
          args: args,
          code: []
        }

        new_obj = %{obj | verbs: obj.verbs ++ [new_verb]}
        new_db = %{state.db | objects: Map.put(state.db.objects, obj_id, new_obj)}
        {:reply, :ok, %{state | db: new_db}}
    end
  end

  @impl true
  def handle_call({:delete_verb, obj_id, verb_name}, _from, state) do
    case Map.get(state.db.objects, obj_id) do
      nil ->
        {:reply, {:error, :E_INVIND}, state}

      obj ->
        new_verbs = Enum.reject(obj.verbs, &Verb.match?(&1, verb_name))
        new_obj = %{obj | verbs: new_verbs}
        new_db = %{state.db | objects: Map.put(state.db.objects, obj_id, new_obj)}
        {:reply, :ok, %{state | db: new_db}}
    end
  end

  @impl true
  def handle_call({:add_property, obj_id, name, value, owner, perms}, _from, state) do
    case Map.get(state.db.objects, obj_id) do
      nil ->
        {:reply, {:error, :E_INVIND}, state}

      obj ->
        new_prop = %Property{
          name: name,
          value: value,
          owner: owner,
          perms: perms
        }

        new_obj = %{obj | properties: obj.properties ++ [new_prop]}
        new_db = %{state.db | objects: Map.put(state.db.objects, obj_id, new_obj)}
        {:reply, :ok, %{state | db: new_db}}
    end
  end

  @impl true
  def handle_call({:delete_property, obj_id, name}, _from, state) do
    case Map.get(state.db.objects, obj_id) do
      nil ->
        {:reply, {:error, :E_INVIND}, state}

      obj ->
        new_props = Enum.reject(obj.properties, &(&1.name == name))
        new_obj = %{obj | properties: new_props}
        new_db = %{state.db | objects: Map.put(state.db.objects, obj_id, new_obj)}
        {:reply, :ok, %{state | db: new_db}}
    end
  end

  @impl true
  def handle_call({:create_object, parent_id, owner_id}, _from, state) do
    new_id = state.db.max_object + 1

    new_obj = %Object{
      id: new_id,
      name: "New Object",
      parent: parent_id,
      owner: owner_id,
      location: -1,
      first_content_id: -1,
      next_id: -1,
      first_child_id: -1,
      sibling_id: -1
    }

    # Update parent's children
    new_db =
      case Map.get(state.db.objects, parent_id) do
        nil ->
          state.db

        parent ->
          new_parent = %{parent | children: parent.children ++ [new_id], first_child_id: new_id}
          %{state.db | objects: Map.put(state.db.objects, parent_id, new_parent)}
      end

    new_db = %{new_db | objects: Map.put(new_db.objects, new_id, new_obj), max_object: new_id}
    {:reply, {:ok, new_id}, %{state | db: new_db}}
  end

  @impl true
  def handle_call({:recycle_object, obj_id}, _from, state) do
    case Map.get(state.db.objects, obj_id) do
      nil ->
        {:reply, {:error, :E_INVIND}, state}

      _obj ->
        # Real recycling would handle contents/children/etc.
        new_objects = Map.delete(state.db.objects, obj_id)
        new_db = %{state.db | objects: new_objects}
        {:reply, :ok, %{state | db: new_db}}
    end
  end

  @impl true
  def handle_call({:change_parent, obj_id, parent_id}, _from, state) do
    case Map.get(state.db.objects, obj_id) do
      nil ->
        {:reply, {:error, :E_INVIND}, state}

      obj ->
        new_obj = %{obj | parent: parent_id}
        new_db = %{state.db | objects: Map.put(state.db.objects, obj_id, new_obj)}
        {:reply, :ok, %{state | db: new_db}}
    end
  end

  @impl true
  def handle_call({:move_object, obj_id, dest_id}, _from, state) do
    case Map.get(state.db.objects, obj_id) do
      nil ->
        {:reply, {:error, :E_INVIND}, state}

      obj ->
        new_obj = %{obj | location: dest_id}
        new_db = %{state.db | objects: Map.put(state.db.objects, obj_id, new_obj)}
        {:reply, :ok, %{state | db: new_db}}
    end
  end

  @impl true
  def handle_call({:set_player_flag, obj_id, value}, _from, state) do
    case perform_set_player_flag(state, obj_id, value) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, err} -> {:reply, {:error, err}, state}
    end
  end

  @impl true
  def handle_call({:chown_object, obj_id, owner_id}, _from, state) do
    case Map.get(state.db.objects, obj_id) do
      nil ->
        {:reply, {:error, :E_INVIND}, state}

      obj ->
        new_obj = %{obj | owner: owner_id}
        new_db = %{state.db | objects: Map.put(state.db.objects, obj_id, new_obj)}
        {:reply, :ok, %{state | db: new_db}}
    end
  end

  @impl true
  def handle_call({:renumber_object, _obj_id}, _from, state) do
    # FUTURE: Placeholder for renumbering logic
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:reset_max_object, _from, state) do
    max_id = Map.keys(state.db.objects) |> Enum.max(fn -> -1 end)
    new_db = %{state.db | max_object: max_id}
    {:reply, :ok, %{state | db: new_db}}
  end

  @impl true
  def handle_cast({:set_verb_ast, obj_id, verb_name, ast}, state) do
    case perform_set_verb_ast(state, obj_id, verb_name, ast) do
      {:ok, new_state} -> {:noreply, new_state}
      _ -> {:noreply, state}
    end
  end

  ## Private Helpers

  defp get_obj(state, id) do
    case Map.get(state.db.objects, id) do
      nil -> {:error, :E_INVIND}
      obj -> {:ok, obj}
    end
  end

  defp find_prop(obj, name) do
    case Enum.find(obj.properties, &(&1.name == name)) do
      nil -> {:error, :E_PROPNF}
      prop -> {:ok, prop}
    end
  end

  defp find_prop_idx(obj, name) do
    case Enum.find_index(obj.properties, &(&1.name == name)) do
      nil -> {:error, :E_PROPNF}
      idx -> {:ok, idx}
    end
  end

  defp find_verb_local(obj, name) do
    case Enum.find(obj.verbs, &Verb.match?(&1, name)) do
      nil -> {:error, :E_VERBNF}
      verb -> {:ok, verb}
    end
  end

  defp find_verb_idx(obj, name) do
    case Enum.find_index(obj.verbs, &Verb.match?(&1, name)) do
      nil -> {:error, :E_VERBNF}
      idx -> {:ok, idx}
    end
  end

  defp update_obj(state, id, obj) do
    new_db = %{state.db | objects: Map.put(state.db.objects, id, obj)}
    %{state | db: new_db}
  end

  defp perform_set_property(state, obj_id, prop_name, value) do
    with {:ok, obj} <- get_obj(state, obj_id) do
      case Enum.find_index(obj.properties, &(&1.name == prop_name)) do
        nil ->
          # Update overridden_properties map
          new_overridden =
            Map.put(obj.overridden_properties, prop_name, %Property{
              name: prop_name,
              value: value
            })

          {:ok, update_obj(state, obj_id, %{obj | overridden_properties: new_overridden})}

        idx ->
          # Update local property
          new_props = List.update_at(obj.properties, idx, &%{&1 | value: value})
          {:ok, update_obj(state, obj_id, %{obj | properties: new_props})}
      end
    end
  end

  defp perform_set_property_info(state, obj_id, prop_name, {owner, perms}) do
    with {:ok, obj} <- get_obj(state, obj_id),
         {:ok, idx} <- find_prop_idx(obj, prop_name) do
      new_props = List.update_at(obj.properties, idx, &%{&1 | owner: owner, perms: perms})
      {:ok, update_obj(state, obj_id, %{obj | properties: new_props})}
    end
  end

  defp perform_set_verb_info(state, obj_id, verb_name, {owner, perms, name}) do
    with {:ok, obj} <- get_obj(state, obj_id),
         {:ok, idx} <- find_verb_idx(obj, verb_name) do
      new_verbs = List.update_at(obj.verbs, idx, &%{&1 | owner: owner, perms: perms, name: name})
      {:ok, update_obj(state, obj_id, %{obj | verbs: new_verbs})}
    end
  end

  defp perform_set_verb_args(state, obj_id, verb_name, args) do
    with {:ok, obj} <- get_obj(state, obj_id),
         {:ok, idx} <- find_verb_idx(obj, verb_name) do
      new_verbs = List.update_at(obj.verbs, idx, &%{&1 | args: args})
      {:ok, update_obj(state, obj_id, %{obj | verbs: new_verbs})}
    end
  end

  defp perform_set_verb_code(state, obj_id, verb_name, code) do
    with {:ok, obj} <- get_obj(state, obj_id),
         {:ok, idx} <- find_verb_idx(obj, verb_name) do
      new_verbs = List.update_at(obj.verbs, idx, &%{&1 | code: code, ast: nil})
      {:ok, update_obj(state, obj_id, %{obj | verbs: new_verbs})}
    end
  end

  defp perform_set_player_flag(state, obj_id, value) do
    with {:ok, obj} <- get_obj(state, obj_id) do
      new_flags =
        case value do
          true -> Flags.set(obj.flags, Flags.user())
          false -> Flags.clear(obj.flags, Flags.user())
          1 -> Flags.set(obj.flags, Flags.user())
          0 -> Flags.clear(obj.flags, Flags.user())
          _ -> Flags.set(obj.flags, Flags.user())
        end

      {:ok, update_obj(state, obj_id, %{obj | flags: new_flags})}
    end
  end

  defp perform_set_verb_ast(state, obj_id, verb_name, ast) do
    with {:ok, obj} <- get_obj(state, obj_id),
         {:ok, idx} <- find_verb_idx(obj, verb_name) do
      new_verbs = List.update_at(obj.verbs, idx, &%{&1 | ast: ast})
      {:ok, update_obj(state, obj_id, %{obj | verbs: new_verbs})}
    end
  end

  defp find_verb_recursive(objects, obj_id, verb_name) do
    case Map.get(objects, obj_id) do
      nil ->
        nil

      obj ->
        case Enum.find(obj.verbs, &Verb.match?(&1, verb_name)) do
          nil -> find_verb_recursive(objects, obj.parent, verb_name)
          verb -> {:ok, obj_id, verb}
        end
    end
  end

  defp find_property_recursive(objects, obj_id, prop_name) do
    case Map.get(objects, obj_id) do
      nil ->
        nil

      obj ->
        lookup_prop_step(objects, obj, prop_name)
    end
  end

  defp lookup_prop_step(objects, obj, prop_name) do
    # Check local properties first
    case Enum.find(obj.properties, &(&1.name == prop_name)) do
      %Property{value: :clear} ->
        find_property_recursive(objects, obj.parent, prop_name)

      prop when not is_nil(prop) ->
        {:ok, prop.value}

      nil ->
        lookup_overridden_prop(objects, obj, prop_name)
    end
  end

  defp lookup_overridden_prop(objects, obj, prop_name) do
    # Check overridden inherited properties
    case Map.get(obj.overridden_properties, prop_name) do
      nil -> find_property_recursive(objects, obj.parent, prop_name)
      prop -> {:ok, prop.value}
    end
  end
end
