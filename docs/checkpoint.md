# Checkpoint Configuration

Alchemoo's checkpoint system provides automatic database snapshots and restoration.

## Configuration Options

```elixir
# config/config.exs
config :alchemoo,
  # MOO name (used in export filenames)
  moo_name: "my-world",
  
  checkpoint: %{
    # Directory for checkpoint files
    dir: "/var/lib/alchemoo/checkpoints",
    
    # Which checkpoint to load on startup
    # Options: :latest, :none, or specific filename
    load_on_startup: :latest,
    
    # Checkpoint interval (milliseconds)
    interval: 300_000,  # 5 minutes
    
    # Keep last N checkpoints (0 = keep all)
    keep_last: 10,
    
    # Checkpoint on shutdown
    checkpoint_on_shutdown: true,
    
    # Export to MOO format every Nth checkpoint (0 = never)
    moo_export_interval: 11,  # Every 11th checkpoint
    
    # Keep last N MOO exports (0 = keep all)
    keep_last_moo_exports: 5
  }
```

## Load on Startup Options

### `:latest` (Default)
Load the most recent checkpoint automatically:

```elixir
config :alchemoo,
  checkpoint: %{
    load_on_startup: :latest
  }
```

### `:none`
Don't load any checkpoint (start with empty database):

```elixir
config :alchemoo,
  checkpoint: %{
    load_on_startup: :none
  }
```

### Specific Checkpoint
Load a particular checkpoint file:

```elixir
config :alchemoo,
  checkpoint: %{
    load_on_startup: "checkpoint-20240115T123045Z.db"
  }
```

## Checkpoint Directory

Checkpoints are stored in the configured directory with timestamped filenames:

```
/var/lib/alchemoo/checkpoints/
├── checkpoint-20240115T120000Z.db
├── checkpoint-20240115T121500Z.db
├── checkpoint-20240115T123000Z.db
└── checkpoint-20240115T123045Z.db  (latest)
```

## Checkpoint Interval

How often to automatically save:

```elixir
# Every 5 minutes (default)
interval: 300_000

# Every 1 minute
interval: 60_000

# Every 30 minutes
interval: 1_800_000

# Disable automatic checkpoints (manual only)
interval: :infinity
```

## Retention Policy

Control how many checkpoints to keep:

```elixir
# Keep last 10 checkpoints (default)
keep_last: 10

# Keep last 50 checkpoints
keep_last: 50

# Keep all checkpoints (never delete)
keep_last: 0
```

Older checkpoints are automatically deleted when the limit is exceeded.

## Manual Checkpoints

Trigger a checkpoint manually:

```elixir
# In IEx - Save checkpoint (ETF format)
iex> Alchemoo.Checkpoint.Server.checkpoint()
{:ok, "checkpoint-20240115T123045Z.db"}

# Export to MOO format (for sharing)
iex> Alchemoo.Checkpoint.Server.export_moo("$XDG_STATE_HOME/alchemoo/my-world.db")
{:ok, "$XDG_STATE_HOME/alchemoo/my-world.db"}

# In MOO code (future)
dump_database()
```

## File Formats

### ETF Format (Default Checkpoints)

Regular checkpoints use Erlang Term Format (ETF):

**Pros:**
- ✅ Fast serialization/deserialization
- ✅ Compact binary format
- ✅ Compressed by default
- ✅ Native Elixir/Erlang support

**Cons:**
- ❌ Not human-readable
- ❌ Elixir/Erlang specific
- ⚠️ ERTS version compatibility

**Compatibility:**
- Uses `minor_version: 2` for better cross-version compatibility
- Generally compatible across ERTS versions
- May have issues with very old/new ERTS versions
- **Recommendation:** Use MOO exports for long-term archival

### MOO Format (Exports)

MOO exports use LambdaMOO Format 4:

**Pros:**
- ✅ Human-readable text format
- ✅ Compatible with other MOO servers
- ✅ Version control friendly
- ✅ Long-term archival safe
- ✅ Platform independent

**Cons:**
- ❌ Slower to parse
- ❌ Larger file size
- ❌ Not suitable for frequent checkpoints

**Use Cases:**
- Sharing databases with others
- Long-term backups
- Version control
- Migration between MOO servers

## Exporting to MOO Format

To share your database with other MOO servers or for backup:

```elixir
# Export current database to MOO format
iex> Alchemoo.Checkpoint.Server.export_moo("/path/to/export.db")
{:ok, "/path/to/export.db"}
```

This creates a LambdaMOO Format 4 database file that can be:
- Loaded by other MOO servers (LambdaMOO, ToastStunt, etc.)
- Shared with other users
- Used as a backup in standard format
- Version controlled (text format)

**Note:** Regular checkpoints use ETF format (faster, Elixir-specific). Use MOO export for sharing/compatibility.

## Automatic MOO Exports

You can configure automatic periodic MOO exports:

```elixir
config :alchemoo,
  moo_name: "my-world",  # Used in export filenames
  
  checkpoint: %{
    moo_export_interval: 11,  # Export every 11th checkpoint
    keep_last_moo_exports: 5   # Keep last 5 MOO exports
  }
```

This creates portable MOO format backups automatically:
- Every 11th checkpoint (default)
- Saved alongside ETF checkpoints
- Named `my-world-TIMESTAMP.db` (using configured moo_name)
- Can be shared with other MOO servers
- Old exports automatically cleaned up

**Example:** With 5-minute checkpoints and interval of 11:
- Checkpoint every 5 minutes (ETF)
- MOO export every 55 minutes (11 × 5)
- Keep last 5 MOO exports (automatic cleanup)
- Automatic portable backups!

Set `moo_export_interval` to `0` to disable automatic MOO exports.

### MOO Export Cleanup

MOO exports are automatically cleaned up based on `keep_last_moo_exports`:
- Default: Keep last 5 MOO exports
- Set to `0` to keep all MOO exports
- Cleanup happens after each new MOO export
- Only affects MOO exports (not ETF checkpoints)

**Example directory:**
```
/var/lib/alchemoo/checkpoints/
├── checkpoint-20240115T120000Z.db  (ETF)
├── checkpoint-20240115T121500Z.db  (ETF)
├── my-world-20240115T120000Z.db    (MOO export #1)
├── my-world-20240115T130000Z.db    (MOO export #2)
└── my-world-20240115T140000Z.db    (MOO export #3)
```

## Listing Checkpoints

See available checkpoints:

```elixir
iex> Alchemoo.Checkpoint.Server.list_checkpoints()
[
  "checkpoint-20240115T123045Z.db",
  "checkpoint-20240115T123000Z.db",
  "checkpoint-20240115T122500Z.db"
]
```

## Loading Checkpoints

Load a specific checkpoint:

```elixir
iex> Alchemoo.Checkpoint.Server.load_checkpoint("checkpoint-20240115T120000Z.db")
{:ok, 95}  # 95 objects loaded
```

## Checkpoint Info

Get checkpoint server status:

```elixir
iex> Alchemoo.Checkpoint.Server.info()
%{
  checkpoint_dir: "/var/lib/alchemoo/checkpoints",
  interval: 300_000,
  keep_last: 10,
  last_checkpoint: "checkpoint-20240115T123045Z.db",
  checkpoint_count: 42,
  available_checkpoints: 10
}
```

## Crash Recovery

**The Database Server automatically reloads the latest checkpoint after a crash.**

If the Database Server crashes and is restarted by the supervisor:
1. Supervisor restarts Database Server
2. Database Server looks for latest checkpoint
3. Automatically loads checkpoint into memory
4. Server continues with restored state

This ensures **no data loss** even if the Database Server crashes between checkpoints.

### How It Works

```elixir
# Database Server init/1
def init(_opts) do
  # Create ETS table
  :ets.new(:alchemoo_objects, [...])
  
  # Auto-load latest checkpoint (crash recovery)
  state = maybe_load_latest_checkpoint(state)
  
  {:ok, state}
end
```

### Configuration

Enable/disable auto-load on restart:

```elixir
config :alchemoo,
  auto_load_checkpoint: true  # default
```

Set to `false` to disable crash recovery (not recommended for production).

### Example Scenario

```
1. Server running with 1000 objects
2. Checkpoint at 12:00 (1000 objects saved)
3. User creates 5 new objects (1005 total)
4. Database Server crashes at 12:03
5. Supervisor restarts Database Server
6. Database Server auto-loads checkpoint from 12:00
7. Server has 1000 objects (5 new objects lost)
8. Next checkpoint at 12:05 saves current state
```

**Data loss window:** Only changes since last checkpoint are lost.

**Mitigation:** Reduce checkpoint interval for critical applications.

By default, Alchemoo checkpoints on shutdown:

```elixir
config :alchemoo,
  checkpoint: %{
    checkpoint_on_shutdown: true  # default
  }
```

This ensures no data loss when stopping the server gracefully.

## Example Configurations

### Development (Frequent Checkpoints)
```elixir
config :alchemoo,
  checkpoint: %{
    dir: "$XDG_STATE_HOME/alchemoo/checkpoints",
    load_on_startup: :latest,
    interval: 60_000,  # 1 minute
    keep_last: 5,
    checkpoint_on_shutdown: true
  }
```

### Production (Conservative)
```elixir
config :alchemoo,
  checkpoint: %{
    dir: "/var/lib/alchemoo/checkpoints",
    load_on_startup: :latest,
    interval: 600_000,  # 10 minutes
    keep_last: 50,
    checkpoint_on_shutdown: true
  }
```

### Testing (No Auto-Load)
```elixir
config :alchemoo,
  checkpoint: %{
    dir: "$XDG_STATE_HOME/alchemoo/test-checkpoints",
    load_on_startup: :none,  # Start fresh
    interval: :infinity,  # Manual only
    keep_last: 0,  # Keep all
    checkpoint_on_shutdown: false
  }
```

### Disaster Recovery (Keep Everything)
```elixir
config :alchemoo,
  checkpoint: %{
    dir: "/mnt/backup/alchemoo/checkpoints",
    load_on_startup: :latest,
    interval: 300_000,  # 5 minutes
    keep_last: 0,  # Never delete
    checkpoint_on_shutdown: true
  }
```

## File Format

Alchemoo supports two checkpoint formats:

### ETF Format (Default)
- **Erlang Term Format** - Binary format
- Fast serialization/deserialization
- Preserves Elixir data structures
- Used for automatic checkpoints
- **Not compatible** with other MOO servers

### MOO Format (Export)
- **LambdaMOO Format 4** - Text format
- Compatible with LambdaMOO, ToastStunt, etc.
- Can be shared and version controlled
- Use `export_moo/1` to create
- Slower than ETF but portable

**When to use each:**
- ETF: Automatic checkpoints, crash recovery (fast)
- MOO: Sharing, backup, compatibility (portable)

## Atomic Writes

Checkpoints use atomic file operations:
1. Write to temporary file (`checkpoint-XXX.db.part`)
2. Atomic rename to final name
3. Never corrupts existing checkpoints

## Performance

Checkpoint performance depends on database size:
- Small (100 objects): ~10ms
- Medium (1000 objects): ~100ms
- Large (10000 objects): ~1s

Checkpoints are non-blocking - the server continues running during saves.

## Crash Recovery

**The Database Server automatically reloads the latest checkpoint after a crash.**

If the Database Server crashes and is restarted by the supervisor:
1. Supervisor restarts Database Server
2. Database Server looks for latest checkpoint
3. Automatically loads checkpoint into memory
4. Server continues with restored state

This ensures **minimal data loss** even if the Database Server crashes between checkpoints.

### Configuration

Enable/disable auto-load on restart:

```elixir
config :alchemoo,
  auto_load_checkpoint: true  # default
```

Set to `false` to disable crash recovery (not recommended for production).

### Example Scenario

```
1. Server running with 1000 objects
2. Checkpoint at 12:00 (1000 objects saved)
3. User creates 5 new objects (1005 total)
4. Database Server crashes at 12:03
5. Supervisor restarts Database Server
6. Database Server auto-loads checkpoint from 12:00
7. Server has 1000 objects (5 new objects lost)
8. Next checkpoint at 12:05 saves current state
```

**Data loss window:** Only changes since last checkpoint are lost.

**Mitigation:** Reduce checkpoint interval for critical applications.

## Troubleshooting

### Checkpoint directory doesn't exist
The directory is created automatically on startup.

### Permission denied
Ensure the Alchemoo process has write access to the checkpoint directory.

### Disk full
Checkpoints will fail if disk is full. Monitor disk space and adjust `keep_last` accordingly.

### Checkpoint not found on startup
If the specified checkpoint doesn't exist, the server logs an error and continues with an empty database.

## See Also

- [Database Server](database.md)
- [Configuration Guide](configuration.md)
