defmodule Alchemoo.Checkpoint.Server do
  @moduledoc """
  Checkpoint Server handles periodic database snapshots and restoration.

  ## Configuration

  ```elixir
  config :alchemoo,
    checkpoint: %{
      # Where to store checkpoints
      dir: "/var/lib/alchemoo/checkpoints",
      
      # Which checkpoint to load on startup
      # Options: :latest, :none, or specific filename
      load_on_startup: :latest,  # or "checkpoint-2024-01-15-12-30-45.db"
      
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

  # CONFIG: Should be extracted to config
  # CONFIG: :alchemoo, :checkpoint, :dir
  @default_checkpoint_dir "/tmp/alchemoo/checkpoints"
  # 307 seconds (prime) # CONFIG: :alchemoo, :checkpoint, :interval
  @default_interval 307_000
  # CONFIG: :alchemoo, :checkpoint, :keep_last
  @default_keep_last 10
  # CONFIG: :alchemoo, :checkpoint, :load_on_startup
  @default_load_on_startup :latest
  # CONFIG: :alchemoo, :checkpoint, :checkpoint_on_shutdown
  @checkpoint_on_shutdown true
  # CONFIG: :alchemoo, :checkpoint, :moo_export_interval (every Nth checkpoint)
  @moo_export_interval 11
  # CONFIG: :alchemoo, :moo_name (used in filenames)
  @moo_name "alchemoo"
  # CONFIG: :alchemoo, :checkpoint, :keep_last_moo_exports
  @keep_last_moo_exports 5

  defstruct [
    :checkpoint_dir,
    :interval,
    :keep_last,
    :timer_ref,
    :moo_export_interval,
    :moo_name,
    :keep_last_moo_exports,
    last_checkpoint: nil,
    checkpoint_count: 0
  ]

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def checkpoint do
    GenServer.call(__MODULE__, :checkpoint, :infinity)
  end

  def export_moo(path) do
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
    checkpoint_dir = Keyword.get(opts, :checkpoint_dir, @default_checkpoint_dir)
    interval = Keyword.get(opts, :interval, @default_interval)
    keep_last = Keyword.get(opts, :keep_last, @default_keep_last)
    _load_on_startup = Keyword.get(opts, :load_on_startup, @default_load_on_startup)
    moo_export_interval = Keyword.get(opts, :moo_export_interval, @moo_export_interval)
    moo_name = Keyword.get(opts, :moo_name, @moo_name)
    keep_last_moo_exports = Keyword.get(opts, :keep_last_moo_exports, @keep_last_moo_exports)

    # Ensure checkpoint directory exists
    File.mkdir_p!(checkpoint_dir)

    state = %__MODULE__{
      checkpoint_dir: checkpoint_dir,
      interval: interval,
      keep_last: keep_last,
      moo_export_interval: moo_export_interval,
      moo_name: moo_name,
      keep_last_moo_exports: keep_last_moo_exports
    }

    # Schedule first checkpoint
    timer_ref = schedule_checkpoint(interval)
    state = %{state | timer_ref: timer_ref}

    Logger.info(
      "Checkpoint server started (dir: #{checkpoint_dir}, interval: #{interval}ms, MOO export every #{moo_export_interval} checkpoints)"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:checkpoint, _from, state) do
    case do_checkpoint(state) do
      {:ok, filename, new_state} ->
        {:reply, {:ok, filename}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:export_moo, path}, _from, state) do
    Logger.info("Exporting database to MOO format: #{path}")

    # Get database snapshot
    db = Server.get_snapshot()

    # Write to MOO format
    case Writer.write_moo(db, path) do
      :ok ->
        Logger.info("Database exported to #{path}")
        {:reply, {:ok, path}, state}

      {:error, reason} ->
        Logger.error("Failed to export database: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_checkpoints, _from, state) do
    checkpoints = list_checkpoint_files(state.checkpoint_dir)
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
      interval: state.interval,
      keep_last: state.keep_last,
      last_checkpoint: state.last_checkpoint,
      checkpoint_count: state.checkpoint_count,
      available_checkpoints: length(list_checkpoint_files(state.checkpoint_dir))
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info(:checkpoint, state) do
    # Periodic checkpoint
    case do_checkpoint(state) do
      {:ok, _filename, new_state} ->
        # Check if we should also export to MOO format
        new_state = maybe_export_moo(new_state)

        # Schedule next checkpoint
        timer_ref = schedule_checkpoint(state.interval)
        {:noreply, %{new_state | timer_ref: timer_ref}}

      {:error, _reason} ->
        # Still schedule next checkpoint even if this one failed
        timer_ref = schedule_checkpoint(state.interval)
        {:noreply, %{state | timer_ref: timer_ref}}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Checkpoint server stopping (reason: #{inspect(reason)})")

    case @checkpoint_on_shutdown do
      true ->
        Logger.info("Performing final checkpoint before shutdown...")

        case do_checkpoint(state) do
          {:ok, filename, _state} ->
            Logger.info("Final checkpoint saved: #{filename}")

          {:error, reason} ->
            Logger.error("Failed to save final checkpoint: #{inspect(reason)}")
        end

      false ->
        :ok
    end

    :ok
  end

  ## Private Helpers

  defp do_checkpoint(state) do
    start_time = System.monotonic_time(:millisecond)

    # Get database snapshot
    db = Server.get_snapshot()
    stats = Server.stats()

    Logger.info(
      "Starting checkpoint ##{state.checkpoint_count + 1} (#{stats.object_count} objects)..."
    )

    # Generate filename with timestamp
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    filename = "checkpoint-#{timestamp}.etf"
    temp_path = Path.join(state.checkpoint_dir, "#{filename}.tmp")
    final_path = Path.join(state.checkpoint_dir, filename)

    # Serialize database
    content = serialize_database(db)
    size_kb = byte_size(content) / 1024

    # Write to temp file
    case File.write(temp_path, content) do
      :ok ->
        # Atomic rename
        case File.rename(temp_path, final_path) do
          :ok ->
            elapsed = System.monotonic_time(:millisecond) - start_time

            Logger.info(
              "Checkpoint ##{state.checkpoint_count + 1} complete: #{filename} (#{Float.round(size_kb, 1)} KB, #{elapsed}ms)"
            )

            # Cleanup old checkpoints
            cleanup_old_checkpoints(state)

            new_state = %{
              state
              | last_checkpoint: filename,
                checkpoint_count: state.checkpoint_count + 1
            }

            {:ok, filename, new_state}

          {:error, reason} ->
            Logger.error("Failed to rename checkpoint: #{inspect(reason)}")
            File.rm(temp_path)
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to write checkpoint: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp serialize_database(db) do
    # Use Erlang term format with options for better compatibility
    # Options:
    #   compressed: Smaller files
    #   minor_version: 2 for better compatibility across ERTS versions
    :erlang.term_to_binary(db, [:compressed, minor_version: 2])
  end

  defp schedule_checkpoint(interval) do
    Process.send_after(self(), :checkpoint, interval)
  end

  defp list_checkpoint_files(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(fn f ->
          String.starts_with?(f, "checkpoint-") and
            (String.ends_with?(f, ".etf") or String.ends_with?(f, ".db"))
        end)
        # Most recent first
        |> Enum.sort(:desc)

      {:error, _} ->
        []
    end
  end

  defp cleanup_old_checkpoints(state) do
    case state.keep_last > 0 do
      true ->
        checkpoints = list_checkpoint_files(state.checkpoint_dir)
        delete_excess_files(checkpoints, state.keep_last, state.checkpoint_dir, "checkpoint")

      false ->
        :ok
    end
  end

  defp delete_excess_files(files, keep_count, dir, type_label) do
    case length(files) > keep_count do
      true ->
        to_delete = Enum.drop(files, keep_count)

        Enum.each(to_delete, fn filename ->
          path = Path.join(dir, filename)
          File.rm(path)
          Logger.info("Deleted old #{type_label}: #{filename}")
        end)

      false ->
        :ok
    end
  end

  defp maybe_export_moo(state) do
    # Export to MOO format every Nth checkpoint
    case state.moo_export_interval > 0 and
           rem(state.checkpoint_count, state.moo_export_interval) == 0 do
      true -> perform_moo_export(state)
      false -> state
    end
  end

  defp perform_moo_export(state) do
    Logger.info("Periodic MOO export (checkpoint ##{state.checkpoint_count})")

    # Generate MOO export filename with moo_name
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    filename = "#{state.moo_name}-#{timestamp}.db"
    path = Path.join(state.checkpoint_dir, filename)

    # Get database and export
    db = Server.get_snapshot()

    case Writer.write_moo(db, path) do
      :ok ->
        Logger.info("MOO export saved: #{filename}")
        cleanup_old_moo_exports(state)

      {:error, reason} ->
        Logger.error("MOO export failed: #{inspect(reason)}")
    end

    state
  end

  defp cleanup_old_moo_exports(state) do
    case state.keep_last_moo_exports > 0 do
      true ->
        moo_exports = list_moo_export_files(state.checkpoint_dir, state.moo_name)

        delete_excess_files(
          moo_exports,
          state.keep_last_moo_exports,
          state.checkpoint_dir,
          "MOO export"
        )

      false ->
        :ok
    end
  end

  defp list_moo_export_files(dir, moo_name) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(fn f ->
          String.starts_with?(f, "#{moo_name}-") and String.ends_with?(f, ".db")
        end)
        # Most recent first
        |> Enum.sort(:desc)

      {:error, _} ->
        []
    end
  end
end
