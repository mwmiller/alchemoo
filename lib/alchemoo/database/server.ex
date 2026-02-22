defmodule Alchemoo.Database.Server do
  @moduledoc """
  The Database Server is the single source of truth for all MOO objects,
  properties, and verbs. It uses ETS for concurrent reads and GenServer
  for serialized writes.
  """
  use GenServer
  require Logger

  alias Alchemoo.Database
  alias Alchemoo.Database.{Object, Property, Verb}

  # CONFIG: Should be extracted to config/config.exs
  @table :alchemoo_objects
  # CONFIG: :alchemoo, :ets_read_concurrency
  @ets_read_concurrency true
  # CONFIG: :alchemoo, :ets_write_concurrency
  @ets_write_concurrency false
  # CONFIG: :alchemoo, :auto_load_checkpoint
  @auto_load_checkpoint true

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def load(path) do
    GenServer.call(__MODULE__, {:load, path}, :infinity)
  end

  def get_object(obj_id) when is_integer(obj_id) do
    case :ets.lookup(@table, obj_id) do
      [{^obj_id, object}] -> {:ok, object}
      [] -> {:error, :E_INVARG}
    end
  end

  @doc "Get property value with inheritance"
  def get_property(obj_id, prop_name) when is_integer(obj_id) and is_binary(prop_name) do
    GenServer.call(__MODULE__, {:get_property, obj_id, prop_name})
  end

  def set_property(obj_id, prop_name, value) when is_integer(obj_id) and is_binary(prop_name) do
    GenServer.call(__MODULE__, {:set_property, obj_id, prop_name, value})
  end

  @doc "Find verb with inheritance"
  def find_verb(obj_id, verb_name) when is_integer(obj_id) and is_binary(verb_name) do
    GenServer.call(__MODULE__, {:find_verb, obj_id, verb_name})
  end

  @doc "Get database snapshot for checkpointing"
  def get_snapshot do
    GenServer.call(__MODULE__, :get_snapshot, :infinity)
  end

  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  def create_object(parent_id) when is_integer(parent_id) do
    GenServer.call(__MODULE__, {:create_object, parent_id})
  end

  def recycle_object(obj_id) when is_integer(obj_id) do
    GenServer.call(__MODULE__, {:recycle_object, obj_id})
  end

  def change_parent(obj_id, new_parent_id)
      when is_integer(obj_id) and is_integer(new_parent_id) do
    GenServer.call(__MODULE__, {:change_parent, obj_id, new_parent_id})
  end

  def move_object(obj_id, dest_id) when is_integer(obj_id) and is_integer(dest_id) do
    GenServer.call(__MODULE__, {:move_object, obj_id, dest_id})
  end

  def add_property(obj_id, prop_name, value, owner, perms)
      when is_integer(obj_id) and is_binary(prop_name) do
    GenServer.call(__MODULE__, {:add_property, obj_id, prop_name, value, owner, perms})
  end

  def delete_property(obj_id, prop_name) when is_integer(obj_id) and is_binary(prop_name) do
    GenServer.call(__MODULE__, {:delete_property, obj_id, prop_name})
  end

  def add_verb(obj_id, verb_name, owner, perms, code)
      when is_integer(obj_id) and is_binary(verb_name) do
    GenServer.call(__MODULE__, {:add_verb, obj_id, verb_name, owner, perms, code})
  end

  def delete_verb(obj_id, verb_name) when is_integer(obj_id) and is_binary(verb_name) do
    GenServer.call(__MODULE__, {:delete_verb, obj_id, verb_name})
  end

  def set_verb_code(obj_id, verb_name, code) when is_binary(verb_name) do
    GenServer.call(__MODULE__, {:set_verb_code, obj_id, verb_name, code})
  end

  def get_verb_info(obj_id, verb_name) when is_binary(verb_name) do
    GenServer.call(__MODULE__, {:get_verb_info, obj_id, verb_name})
  end

  def set_verb_info(obj_id, verb_name, info) when is_binary(verb_name) do
    GenServer.call(__MODULE__, {:set_verb_info, obj_id, verb_name, info})
  end

  def get_verb_args(obj_id, verb_name) when is_binary(verb_name) do
    GenServer.call(__MODULE__, {:get_verb_args, obj_id, verb_name})
  end

  def set_verb_args(obj_id, verb_name, args) when is_binary(verb_name) do
    GenServer.call(__MODULE__, {:set_verb_args, obj_id, verb_name, args})
  end

  def set_player_flag(obj_id, flag) when is_integer(obj_id) and is_boolean(flag) do
    GenServer.call(__MODULE__, {:set_player_flag, obj_id, flag})
  end

  def is_clear_property?(obj_id, prop_name) when is_binary(prop_name) do
    GenServer.call(__MODULE__, {:is_clear_property, obj_id, prop_name})
  end

  def get_property_info(obj_id, prop_name) when is_binary(prop_name) do
    GenServer.call(__MODULE__, {:get_property_info, obj_id, prop_name})
  end

  def set_property_info(obj_id, prop_name, info) when is_binary(prop_name) do
    GenServer.call(__MODULE__, {:set_property_info, obj_id, prop_name, info})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Create ETS table for objects
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: @ets_read_concurrency,
      write_concurrency: @ets_write_concurrency
    ])

    state = %{
      loaded: false,
      object_count: 0,
      # Highest object ID ever created
      max_object: -1,
      # List of recycled object IDs available for reuse
      recycled_objects: [],
      db_path: nil
    }

    # Auto-load checkpoint on restart (for crash recovery)
    state =
      case @auto_load_checkpoint do
        true -> maybe_load_latest_checkpoint(state)
        false -> state
      end

    # Auto-load if path provided (overrides checkpoint)
    # CONFIG: auto_load_db should be extracted to config
    case Keyword.get(opts, :db_path) do
      nil -> {:ok, state}
      path -> handle_call({:load, path}, nil, state)
    end
  end

  @impl true
  def handle_call({:load, path}, _from, state) do
    Logger.info("Loading database from #{path}")

    case File.read(path) do
      {:ok, binary} ->
        detect_and_load(binary, path, state)

      {:error, reason} ->
        Logger.error("Failed to read database file: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_property, obj_id, prop_name}, _from, state) do
    result = do_get_property(obj_id, prop_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_property, obj_id, prop_name, value}, _from, state) do
    result = do_set_property(obj_id, prop_name, value)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:find_verb, obj_id, verb_name}, _from, state) do
    result = do_find_verb(obj_id, verb_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_snapshot, _from, state) do
    # Collect all objects from ETS
    objects =
      :ets.tab2list(@table)
      |> Map.new()

    db = %Database{objects: objects}
    {:reply, db, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      loaded: state.loaded,
      object_count: state.object_count,
      max_object: state.max_object,
      recycled_count: length(state.recycled_objects),
      db_path: state.db_path,
      ets_size: :ets.info(@table, :size),
      ets_memory: :ets.info(@table, :memory)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:create_object, parent_id}, _from, state) do
    # Allocate new object ID
    {new_id, new_state} = allocate_object_id(state)

    # Create new object
    new_object = %Object{
      id: new_id,
      name: "object",
      parent: parent_id,
      # TODO: Should be caller
      owner: new_id,
      location: -1,
      contents: [],
      properties: [],
      verbs: []
    }

    :ets.insert(@table, {new_id, new_object})

    new_state = %{new_state | object_count: new_state.object_count + 1}
    {:reply, {:ok, new_id}, new_state}
  end

  @impl true
  def handle_call({:recycle_object, obj_id}, _from, state) do
    case get_object(obj_id) do
      {:ok, _object} ->
        # TODO: Check if it's a player (can't recycle players)
        # TODO: Remove from parent's contents
        # TODO: Move contents elsewhere

        :ets.delete(@table, obj_id)

        new_state = %{
          state
          | object_count: state.object_count - 1,
            recycled_objects: [obj_id | state.recycled_objects]
        }

        {:reply, :ok, new_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:change_parent, obj_id, new_parent_id}, _from, state) do
    case get_object(obj_id) do
      {:ok, object} ->
        new_object = %{object | parent: new_parent_id}
        :ets.insert(@table, {obj_id, new_object})
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:move_object, obj_id, dest_id}, _from, state) do
    case get_object(obj_id) do
      {:ok, object} ->
        # TODO: Update old location's contents
        # TODO: Update new location's contents

        new_object = %{object | location: dest_id}
        :ets.insert(@table, {obj_id, new_object})
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:add_property, obj_id, prop_name, value, owner, perms}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> perform_add_property(obj_id, object, prop_name, value, owner, perms)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_property, obj_id, prop_name}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> perform_delete_property(obj_id, object, prop_name)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:add_verb, obj_id, verb_name, owner, perms, code}, _from, state) do
    case get_object(obj_id) do
      {:ok, object} ->
        perform_add_verb(obj_id, object, verb_name, owner, perms, code)
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:delete_verb, obj_id, verb_name}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> perform_delete_verb(obj_id, object, verb_name)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_verb_code, obj_id, verb_name, code}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> perform_set_verb_code(obj_id, object, verb_name, code)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_verb_info, obj_id, verb_name}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> lookup_verb_info(object, verb_name)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_verb_info, obj_id, verb_name, info}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> perform_set_verb_info(obj_id, object, verb_name, info)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_verb_args, obj_id, verb_name}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> lookup_verb_args(object, verb_name)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_verb_args, obj_id, verb_name, args}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> perform_set_verb_args(obj_id, object, verb_name, args)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_player_flag, obj_id, flag}, _from, state) do
    import Bitwise

    result =
      case get_object(obj_id) do
        {:ok, object} ->
          new_flags =
            case flag do
              true -> object.flags ||| 1
              false -> object.flags &&& bnot(1)
            end

          new_object = %{object | flags: new_flags}
          :ets.insert(@table, {obj_id, new_object})
          :ok

        error ->
          error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:is_clear_property, obj_id, prop_name}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> check_is_property_clear(object, prop_name)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_property_info, obj_id, prop_name}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> lookup_property_info(object, prop_name)
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_property_info, obj_id, prop_name, info}, _from, state) do
    result =
      case get_object(obj_id) do
        {:ok, object} -> perform_set_property_info(obj_id, object, prop_name, info)
        error -> error
      end

    {:reply, result, state}
  end

  ## Private Helpers

  defp maybe_load_latest_checkpoint(state) do
    checkpoint_dir = Application.get_env(:alchemoo, :checkpoint_dir, "/tmp/alchemoo/checkpoints")

    case find_latest_checkpoint(checkpoint_dir) do
      nil ->
        Logger.info("No checkpoint found for auto-load")
        state

      filename ->
        load_checkpoint_file(state, checkpoint_dir, filename)
    end
  end

  defp load_checkpoint_file(state, dir, filename) do
    path = Path.join(dir, filename)
    Logger.info("Auto-loading checkpoint after restart: #{filename}")

    case File.read(path) do
      {:ok, binary} ->
        db = :erlang.binary_to_term(binary)
        apply_checkpoint_to_ets(state, db, path)

      {:error, reason} ->
        Logger.error("Failed to load checkpoint: #{inspect(reason)}")
        state
    end
  end

  defp apply_checkpoint_to_ets(state, db, path) do
    :ets.delete_all_objects(@table)

    Enum.each(db.objects, fn {obj_id, object} ->
      :ets.insert(@table, {obj_id, object})
    end)

    count = map_size(db.objects)

    max_obj =
      case count > 0 do
        true -> db.objects |> Map.keys() |> Enum.max()
        false -> -1
      end

    Logger.info("Loaded #{count} objects from checkpoint (max object: ##{max_obj})")

    %{
      state
      | loaded: true,
        object_count: count,
        max_object: max_obj,
        # TODO: Persist recycled list in checkpoints
        recycled_objects: [],
        db_path: path
    }
  end

  defp find_latest_checkpoint(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(fn f ->
          String.starts_with?(f, "checkpoint-") and
            (String.ends_with?(f, ".etf") or String.ends_with?(f, ".db"))
        end)
        |> Enum.sort(:desc)
        |> List.first()

      {:error, _} ->
        nil
    end
  end

  defp detect_and_load(<<131, _::binary>> = binary, path, state) do
    Logger.info("Detected ETF checkpoint format")
    db = :erlang.binary_to_term(binary)
    load_db_into_ets(db, path, state, "ETF checkpoint")
  end

  defp detect_and_load(binary, path, state) do
    case Database.Parser.parse(binary) do
      {:ok, db} ->
        load_db_into_ets(db, path, state, "MOO database")

      {:error, reason} ->
        Logger.error("Failed to load database: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  defp load_db_into_ets(db, path, state, type_name) do
    :ets.delete_all_objects(@table)

    Enum.each(db.objects, fn {obj_id, object} ->
      :ets.insert(@table, {obj_id, object})
    end)

    count = map_size(db.objects)

    max_obj =
      case count > 0 do
        true -> db.objects |> Map.keys() |> Enum.max()
        false -> -1
      end

    Logger.info("Loaded #{count} objects from #{type_name} (max object: ##{max_obj})")

    new_state = %{
      state
      | loaded: true,
        object_count: count,
        max_object: max_obj,
        recycled_objects: [],
        db_path: path
    }

    {:reply, {:ok, count}, new_state}
  end

  defp lookup_verb_info(object, verb_name) do
    case Enum.find(object.verbs, fn v -> v.name == verb_name end) do
      nil -> {:error, :E_VERBNF}
      verb -> {:ok, {verb.owner, verb.perms, verb.name}}
    end
  end

  defp lookup_verb_args(object, verb_name) do
    case Enum.find(object.verbs, fn v -> v.name == verb_name end) do
      nil -> {:error, :E_VERBNF}
      verb -> {:ok, verb.args}
    end
  end

  defp check_is_property_clear(object, prop_name) do
    case Enum.find(object.properties, fn p -> p.name == prop_name end) do
      nil -> {:error, :E_PROPNF}
      prop -> {:ok, prop.value == :clear}
    end
  end

  defp lookup_property_info(object, prop_name) do
    case Enum.find(object.properties, fn p -> p.name == prop_name end) do
      nil -> {:error, :E_PROPNF}
      prop -> {:ok, {prop.owner, prop.perms}}
    end
  end

  defp perform_set_verb_code(obj_id, object, verb_name, code) do
    case Enum.find_index(object.verbs, fn v -> v.name == verb_name end) do
      nil ->
        {:error, :E_VERBNF}

      idx ->
        new_verbs =
          List.update_at(object.verbs, idx, fn verb ->
            %{verb | code: code}
          end)

        new_object = %{object | verbs: new_verbs}
        :ets.insert(@table, {obj_id, new_object})
        :ok
    end
  end

  defp perform_set_verb_info(obj_id, object, verb_name, {owner, perms, new_name}) do
    case Enum.find_index(object.verbs, fn v -> v.name == verb_name end) do
      nil ->
        {:error, :E_VERBNF}

      idx ->
        new_verbs =
          List.update_at(object.verbs, idx, fn verb ->
            %{verb | owner: owner, perms: perms, name: new_name}
          end)

        new_object = %{object | verbs: new_verbs}
        :ets.insert(@table, {obj_id, new_object})
        :ok
    end
  end

  defp perform_set_verb_args(obj_id, object, verb_name, args) do
    case Enum.find_index(object.verbs, fn v -> v.name == verb_name end) do
      nil ->
        {:error, :E_VERBNF}

      idx ->
        new_verbs =
          List.update_at(object.verbs, idx, fn verb ->
            %{verb | args: args}
          end)

        new_object = %{object | verbs: new_verbs}
        :ets.insert(@table, {obj_id, new_object})
        :ok
    end
  end

  defp perform_set_property_info(obj_id, object, prop_name, {owner, perms}) do
    case Enum.find_index(object.properties, fn p -> p.name == prop_name end) do
      nil ->
        {:error, :E_PROPNF}

      idx ->
        new_props =
          List.update_at(object.properties, idx, fn prop ->
            %{prop | owner: owner, perms: perms}
          end)

        new_object = %{object | properties: new_props}
        :ets.insert(@table, {obj_id, new_object})
        :ok
    end
  end

  defp perform_add_property(obj_id, object, prop_name, value, owner, perms) do
    case Enum.any?(object.properties, fn p -> p.name == prop_name end) do
      true ->
        {:error, :E_INVARG}

      false ->
        new_prop = %Property{
          name: prop_name,
          value: value,
          owner: owner,
          perms: perms
        }

        new_object = %{object | properties: object.properties ++ [new_prop]}
        :ets.insert(@table, {obj_id, new_object})
        :ok
    end
  end

  defp perform_delete_property(obj_id, object, prop_name) do
    new_props = Enum.reject(object.properties, fn p -> p.name == prop_name end)

    case length(new_props) == length(object.properties) do
      true ->
        {:error, :E_PROPNF}

      false ->
        new_object = %{object | properties: new_props}
        :ets.insert(@table, {obj_id, new_object})
        :ok
    end
  end

  defp perform_add_verb(obj_id, object, verb_name, owner, perms, code) do
    new_verb = %Verb{
      name: verb_name,
      owner: owner,
      perms: perms,
      prep: 0,
      code: code
    }

    new_object = %{object | verbs: object.verbs ++ [new_verb]}
    :ets.insert(@table, {obj_id, new_object})
  end

  defp perform_delete_verb(obj_id, object, verb_name) do
    new_verbs = Enum.reject(object.verbs, fn v -> v.name == verb_name end)

    case length(new_verbs) == length(object.verbs) do
      true ->
        {:error, :E_VERBNF}

      false ->
        new_object = %{object | verbs: new_verbs}
        :ets.insert(@table, {obj_id, new_object})
        :ok
    end
  end

  defp allocate_object_id(state) do
    case state.recycled_objects do
      [id | rest] ->
        # Reuse recycled ID
        {id, %{state | recycled_objects: rest}}

      [] ->
        # Allocate new ID
        new_id = state.max_object + 1
        {new_id, %{state | max_object: new_id}}
    end
  end

  defp do_get_property(obj_id, prop_name) do
    case get_object(obj_id) do
      {:ok, object} ->
        lookup_property_on_object(object, prop_name)

      error ->
        error
    end
  end

  defp lookup_property_on_object(object, prop_name) do
    case Enum.find(object.properties, fn p -> p.name == prop_name end) do
      %Property{value: :clear} -> check_parent_property(object.parent, prop_name)
      %Property{value: value} -> {:ok, value}
      nil -> check_parent_property(object.parent, prop_name)
    end
  end

  defp check_parent_property(-1, _prop_name), do: {:error, :E_PROPNF}

  defp check_parent_property(parent_id, prop_name) do
    do_get_property(parent_id, prop_name)
  end

  defp do_set_property(obj_id, prop_name, value) do
    case get_object(obj_id) do
      {:ok, object} ->
        update_object_property(obj_id, object, prop_name, value)

      error ->
        error
    end
  end

  defp update_object_property(obj_id, object, prop_name, value) do
    case Enum.find_index(object.properties, fn p -> p.name == prop_name end) do
      nil ->
        {:error, :E_PROPNF}

      idx ->
        new_props =
          List.update_at(object.properties, idx, fn prop ->
            %{prop | value: value}
          end)

        new_object = %{object | properties: new_props}
        :ets.insert(@table, {obj_id, new_object})
        {:ok, value}
    end
  end

  defp do_find_verb(obj_id, verb_name) do
    case get_object(obj_id) do
      {:ok, object} ->
        lookup_verb_on_object(obj_id, object, verb_name)

      error ->
        error
    end
  end

  defp lookup_verb_on_object(obj_id, object, verb_name) do
    case Enum.find(object.verbs, fn v -> matches_verb?(v, verb_name) end) do
      %Verb{} = verb -> {:ok, obj_id, verb}
      nil -> check_parent_verb(object.parent, verb_name)
    end
  end

  defp check_parent_verb(-1, _verb_name), do: {:error, :E_VERBNF}

  defp check_parent_verb(parent_id, verb_name) do
    do_find_verb(parent_id, verb_name)
  end

  defp matches_verb?(%Verb{name: name}, verb_name) do
    # Simple exact match for now
    # TODO: Handle verb name patterns (e.g., "get/take")
    name == verb_name
  end
end
