# Alchemoo

A modern, high-performance LambdaMOO-compatible server built on the Erlang BEAM VM.

**Version:** 0.6.0  

## Features

- ✅ **Full MOO Database Support** - Loads LambdaCore, JHCore, and other MOO databases (Format 4)
- ✅ **Complete MOO Language** - Parser and interpreter with all 5 value types
- ✅ **Command Execution** - Full command parsing and verb execution pipeline
- ✅ **Network Layer** - Unified Telnet and SSH support with transport-agnostic handling
- ✅ **Secure Auth** - SSH public key and password authentication with character integration
- ✅ **Task System** - Concurrent task execution with tick quotas and limits
- ✅ **Built-in Functions** - 144/144 implemented, including standard, extended, and SSH management functions
- ✅ **Unicode Support** - Full UTF-8 with grapheme-aware string operations
- ✅ **Automatic Checkpoints** - Periodic saves with crash recovery (prime-number intervals)
- ✅ **MOO Export** - Export databases in LambdaMOO Format 4
- ✅ **Connection Management** - Advanced session takeover and logout handling
- ✅ **Fingerprint Art** - SSH key identification via 'drunken bishop' visualizations

## Status

**Working MOO Server**

Alchemoo is now a functional MOO server that can:
- Load existing MOO databases
- Accept player connections via Telnet
- Parse and execute commands
- Run verb code from the database
- Send output to players
- Handle multiple concurrent players
- Automatically checkpoint and recover from crashes

**Current Test Status (this branch, Feb 26, 2026):** 144 tests, 0 failures  
**Commits:** 70+

## Quick Start

```bash
# Install dependencies
mix deps.get

# Load a MOO database (optional)
# Place your .db file in ${XDG_STATE_HOME:-$HOME/.local/state}/alchemoo/

# Start the server
mix run --no-halt

# Connect via telnet
telnet localhost 7777
```

## Architecture

```
Player (telnet) → Connection.Handler → Command.Parser → Command.Executor
                                                              ↓
                                                         Database.Server
                                                              ↓
                                                         TaskSupervisor
                                                              ↓
                                                         Task (executes verb)
                                                              ↓
                                                         notify() → Player
```

## Documentation

- **[Getting Started](docs/getting-started.md)** - Complete setup guide for new users
- **[Project Summary](docs/PROJECT_SUMMARY.md)** - Comprehensive project overview
- [Commands](docs/commands.md) - Command parsing and execution
- [Implementation Status](docs/status.md) - Current capabilities and known issues
- [Checkpoint System](docs/checkpoint.md) - Automatic saves and recovery
- [Built-in Functions](docs/builtins-status.md) - Implementation status
- [Unicode Support](docs/unicode.md) - UTF-8 and grapheme handling
- [Network Configuration](docs/network-config.md) - Telnet/SSH/WebSocket setup
- [Database Parser](docs/parser.md) - Database format and parser behavior
- [Ecosystem Guide](docs/ECOSYSTEM.md) - Overview of MOO cores and resources

## Configuration

All configuration is marked with `# CONFIG:` comments for easy extraction:

```elixir
# CONFIG: MOO world name (shown in banner and exports)
config :alchemoo, :moo_name, "MyMOO"

# CONFIG: Welcome text (shown in login banner if database doesn't provide one)
config :alchemoo, :welcome_text, "Welcome to our world!"

# CONFIG: Base directory for persistent data
config :alchemoo, :base_dir, Path.join(System.get_env("XDG_STATE_HOME") || Path.join(System.user_home!(), ".local/state"), "alchemoo")

# CONFIG: Checkpoint settings
config :alchemoo, :checkpoint,
  interval: 300_000,  # 5 minutes
  keep_last: 5,
  moo_export_interval: 11,
  keep_last_moo_exports: 3

# CONFIG: Network settings
config :alchemoo, :network,
  telnet: %{enabled: true, port: 7777},
  ssh: %{enabled: false, port: 2222}

# CONFIG: Task limits
config :alchemoo, :default_tick_quota, 10_000
config :alchemoo, :max_tasks_per_player, 10
```

**Note:** The welcome message is read from `$login.welcome_message` in the database if available, falling back to the configured banner.
```

## Development

```bash
# Run tests
mix test

# Run specific test file
mix test test/alchemoo/command/parser_test.exs

# Compile
mix compile

# Format code
mix format

# Run demos
elixir examples/database_server_demo.exs
elixir examples/task_demo.exs
```

## Roadmap

### Phase 1: Core Infrastructure ✅
- [x] Database parser (Format 4)
- [x] MOO language parser
- [x] MOO interpreter
- [x] Database server with ETS
- [x] Task system with tick quotas
- [x] Connection handling
- [x] Network layer (Telnet)
- [x] Checkpoint system
- [x] MOO database export
- [x] Command execution
- [x] Registry-based task tracking

### Phase 2: Built-in Functions ✅
- [x] Critical built-ins (Complete!)
- [x] Important built-ins (Complete!)
- [x] Math & Extended Math (Complete!)
- [x] Player & Connection Management (Complete!)
- [x] Task Management (Complete!)

### Phase 3: Polish & Enhancement
- [x] Authentication system
- [x] Configuration extraction (via config.exs)
- [x] SSH support (Public Key & Password)
- [x] Automated SSH key registration
- [x] Object matching in commands
- [ ] Preposition validation
- [ ] Performance optimization
- [ ] WebSocket support
- [ ] Implement remaining network stubs (listen/unlisten)

## License

MIT
