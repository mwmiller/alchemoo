defmodule Alchemoo.Checkpoint.Server do
  @moduledoc """
  Checkpoint Server handles periodic database snapshots and restoration.

  ## Configuration

  ```elixir
  config :alchemoo,
    checkpoint: %{
      # Where to store checkpoints
      dir: "$XDG_STATE_HOME/alchemoo/checkpoints",
      
      # How often to checkpoint (milliseconds)
      interval: 300_000,  # 5 minutes
      
      # Keep last N checkpoints (0 = keep all)
      keep_last: 10,
      
      # Checkpoint on shutdown
      checkpoint_on_shutdown: true
    }
  ```
  """
  use GenServer
  require Logger

  alias Alchemoo.Database.Server
  alias Alchemoo.Database.Writer

  defp default_checkpoint_dir, do: "checkpoints"
  # ETF every ~5 mins (prime)
  defp default_etf_interval, do: 307_000
  # MOO every ~1 hour (prime)
  defp default_moo_interval, do: 3_607_000
  defp default_keep_last_etf, do: 10
  defp default_moo_name, do: "alchemoo"
  defp default_keep_last_moo, do: 5

  defstruct [
    :checkpoint_dir,
    :etf_interval,
    :moo_interval,
    :keep_last_etf,
    :etf_timer,
    :moo_timer,
    :moo_name,
    :keep_last_moo,
    checkpoint_count: 0,
    moo_count: 0
  ]

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def checkpoint do
    GenServer.call(__MODULE__, :checkpoint, :infinity)
  end

  def export_moo(path \\ nil) do
    GenServer.call(__MODULE__, {:export_moo, path}, :infinity)
  end

  def list_checkpoints do
    GenServer.call(__MODULE__, :list_checkpoints)
  end

  def load_checkpoint(filename) do
    GenServer.call(__MODULE__, {:load_checkpoint, filename}, :infinity)
  end

  def info do
    GenServer.call(__MODULE__, :info)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    state = build_initial_state(opts)

    # Ensure checkpoint directory exists
    File.mkdir_p!(state.checkpoint_dir)

    # Schedule timers
    etf_timer = schedule_next(:etf_checkpoint, state.etf_interval)
    moo_timer = schedule_next(:moo_checkpoint, state.moo_interval)

    state = %{state | etf_timer: etf_timer, moo_timer: moo_timer}

    Logger.info(
      "Checkpoint server started (dir: #{state.checkpoint_dir}, ETF interval: #{state.etf_interval}ms, MOO interval: #{state.moo_interval}ms)"
    )

    {:ok, state}
  end

  defp build_initial_state(opts) do
    config = Application.get_env(:alchemoo, :checkpoint, [])
    base_dir = Application.get_env(:alchemoo, :base_dir, default_base_dir())

    %__MODULE__{
      checkpoint_dir:
        fetch_config(
          opts,
          config,
          :checkpoint_dir,
          :dir,
          Path.join(base_dir, default_checkpoint_dir())
        ),
      etf_interval: fetch_config(opts, config, :etf_interval, :interval, default_etf_interval()),
      moo_interval:
        fetch_config(opts, config, :moo_interval, :moo_interval, default_moo_interval()),
      keep_last_etf:
        fetch_config(opts, config, :keep_last_etf, :keep_last, default_keep_last_etf()),
      moo_name:
        opts[:moo_name] || Application.get_env(:alchemoo, :moo_name) || default_moo_name(),
      keep_last_moo:
        fetch_config(
          opts,
          config,
          :keep_last_moo,
          :keep_last_moo_exports,
          default_keep_last_moo()
        )
    }
  end

  defp default_base_dir do
    state_home =
      System.get_env("XDG_STATE_HOME") || Path.join(System.user_home!(), ".local/state")

    Path.join(state_home, "alchemoo")
  end

  defp fetch_config(opts, config, key, config_key, default) do
    opts[key] || config[config_key] || default
  end

  @impl true
  def handle_call(:checkpoint, _from, state) do
    case do_etf_checkpoint(state) do
      {:ok, filename, new_state} ->
        {:reply, {:ok, filename}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:export_moo, path}, _from, state) do
    path = path || generate_moo_path(state)

    case perform_moo_export(state, path) do
      {:ok, path, new_state} -> {:reply, {:ok, path}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_checkpoints, _from, state) do
    checkpoints = list_all_files(state.checkpoint_dir)
    {:reply, checkpoints, state}
  end

  @impl true
  def handle_call({:load_checkpoint, filename}, _from, state) do
    path = Path.join(state.checkpoint_dir, filename)

    case Server.load(path) do
      {:ok, count} ->
        Logger.info("Loaded checkpoint: #{filename} (#{count} objects)")
        {:reply, {:ok, count}, state}

      {:error, reason} ->
        Logger.error("Failed to load checkpoint #{filename}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      checkpoint_dir: state.checkpoint_dir,
      etf_interval: state.etf_interval,
      moo_interval: state.moo_interval,
      keep_last_etf: state.keep_last_etf,
      checkpoint_count: state.checkpoint_count,
      moo_count: state.moo_count
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info(:etf_checkpoint, state) do
    case do_etf_checkpoint(state) do
      {:ok, _filename, new_state} ->
        timer = schedule_next(:etf_checkpoint, state.etf_interval)
        {:noreply, %{new_state | etf_timer: timer}}

      {:error, _reason} ->
        timer = schedule_next(:etf_checkpoint, state.etf_interval)
        {:noreply, %{state | etf_timer: timer}}
    end
  end

  @impl true
  def handle_info(:moo_checkpoint, state) do
    path = generate_moo_path(state)

    case perform_moo_export(state, path) do
      {:ok, _, new_state} ->
        timer = schedule_next(:moo_checkpoint, state.moo_interval)
        {:noreply, %{new_state | moo_timer: timer}}

      _ ->
        timer = schedule_next(:moo_checkpoint, state.moo_interval)
        {:noreply, %{state | moo_timer: timer}}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Checkpoint server stopping (reason: #{inspect(reason)})")

    config = Application.get_env(:alchemoo, :checkpoint, [])

    if Keyword.get(config, :checkpoint_on_shutdown, true) do
      Logger.info("Performing final ETF checkpoint before shutdown...")
      do_etf_checkpoint(state)
    end

    :ok
  end

  ## Private Helpers

  defp do_etf_checkpoint(state) do
    start_time = System.monotonic_time(:millisecond)
    File.mkdir_p!(state.checkpoint_dir)

    db = Server.get_snapshot()
    stats = Server.stats()

    if stats.object_count == 0 do
      Logger.warning("Skipping ETF checkpoint: database is empty")
      {:error, :empty_database}
    else
      Logger.info(
        "ETF Checkpoint ##{state.checkpoint_count + 1} (#{stats.object_count} objects)..."
      )

      timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
      filename = "checkpoint-#{timestamp}.etf"
      temp_path = Path.join(state.checkpoint_dir, "#{filename}.part")
      final_path = Path.join(state.checkpoint_dir, filename)

      content = :erlang.term_to_binary(db, [:compressed, minor_version: 2])
      size_kb = byte_size(content) / 1024

      case write_checkpoint_file(temp_path, final_path, content) do
        :ok ->
          elapsed = System.monotonic_time(:millisecond) - start_time

          Logger.info(
            "ETF Checkpoint complete: #{filename} (#{Float.round(size_kb, 1)} KB, #{elapsed}ms)"
          )

          cleanup_etf_checkpoints(state)
          {:ok, filename, %{state | checkpoint_count: state.checkpoint_count + 1}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp write_checkpoint_file(temp_path, final_path, content) do
    case File.write(temp_path, content) do
      :ok ->
        case File.rename(temp_path, final_path) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to rename ETF checkpoint: #{inspect(reason)}")
            File.rm(temp_path)
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to write ETF checkpoint: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp perform_moo_export(state, path) do
    db = Server.get_snapshot()
    stats = Server.stats()

    if stats.object_count == 0 do
      Logger.warning("Skipping MOO export: database is empty")
      {:error, :empty_database}
    else
      Logger.info("MOO Export ##{state.moo_count + 1} to #{path}...")

      case Writer.write_moo(db, path) do
        :ok ->
          Logger.info("MOO export saved: #{Path.basename(path)}")
          cleanup_moo_exports(state)
          {:ok, path, %{state | moo_count: state.moo_count + 1}}

        {:error, reason} ->
          Logger.error("MOO export failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp generate_moo_path(state) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    Path.join(state.checkpoint_dir, "#{state.moo_name}-#{timestamp}.db")
  end

  defp schedule_next(msg, interval) do
    Process.send_after(self(), msg, interval)
  end

  defp list_all_files(dir) do
    case File.ls(dir) do
      {:ok, files} -> Enum.sort(files, :desc)
      _ -> []
    end
  end

  defp cleanup_etf_checkpoints(state) do
    if state.keep_last_etf > 0 do
      files =
        list_all_files(state.checkpoint_dir)
        |> Enum.filter(&String.ends_with?(&1, ".etf"))

      delete_excess_files(files, state.keep_last_etf, state.checkpoint_dir, "ETF")
    end
  end

  defp cleanup_moo_exports(state) do
    if state.keep_last_moo > 0 do
      files =
        list_all_files(state.checkpoint_dir)
        |> Enum.filter(
          &(String.starts_with?(&1, state.moo_name) and String.ends_with?(&1, ".db"))
        )

      # Retention policy: Keep last N, BUT also ensure at least one from > 24h ago
      now = System.system_time(:second)
      one_day_ago = now - 86_400

      {to_keep, to_maybe_delete} = Enum.split(files, state.keep_last_moo)
      final_to_delete = identify_moo_files_to_delete(to_keep, to_maybe_delete, state, one_day_ago)

      Enum.each(final_to_delete, fn f ->
        File.rm(Path.join(state.checkpoint_dir, f))
        Logger.info("Deleted old MOO export: #{f}")
      end)
    end
  end

  defp identify_moo_files_to_delete(to_keep, to_maybe_delete, state, one_day_ago) do
    if Enum.any?(to_keep, &file_older_than?(&1, state.checkpoint_dir, one_day_ago)) do
      to_maybe_delete
    else
      # Find the newest file in the delete list that IS older than 24h
      case Enum.find(
             to_maybe_delete,
             &file_older_than?(&1, state.checkpoint_dir, one_day_ago)
           ) do
        # No old files at all
        nil -> to_maybe_delete
        old_one -> List.delete(to_maybe_delete, old_one)
      end
    end
  end

  defp file_older_than?(filename, dir, timestamp) do
    case File.stat(Path.join(dir, filename)) do
      {:ok, stat} ->
        # stat.mtime is already a NaiveDateTime in newer Elixir
        DateTime.from_naive!(stat.mtime, "Etc/UTC")
        |> DateTime.to_unix()
        |> Kernel.<(timestamp)

      _ ->
        false
    end
  end

  defp delete_excess_files(files, keep_count, dir, type_label) do
    if length(files) > keep_count do
      Enum.drop(files, keep_count)
      |> Enum.each(fn f ->
        File.rm(Path.join(dir, f))
        Logger.info("Deleted old #{type_label}: #{f}")
      end)
    end
  end
end
