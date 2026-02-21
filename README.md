# Alchemoo

A modern, high-performance LambdaMOO-compatible server built on the Erlang BEAM VM.

## Features

- ✅ **Full MOO Database Support** - Loads LambdaCore, JHCore, and other MOO databases (Format 1 & 4)
- ✅ **Complete MOO Language** - Parser and interpreter with all 5 value types
- ✅ **Command Execution** - Full command parsing and verb execution pipeline
- ✅ **Network Layer** - Telnet support (port 7777), SSH/WebSocket ready
- ✅ **Task System** - Concurrent task execution with tick quotas and limits
- ✅ **Built-in Functions** - 36/150 implemented (24%), including all critical functions
- ✅ **Unicode Support** - Full UTF-8 with grapheme-aware string operations
- ✅ **Automatic Checkpoints** - Periodic saves with crash recovery
- ✅ **MOO Export** - Export databases in LambdaMOO Format 4
- ✅ **Connection Management** - Multiple simultaneous players
- ✅ **Registry-based Tracking** - Inspectable task management

## Status

**Working MOO Server!** 🎉

Alchemoo is now a functional MOO server that can:
- Load existing MOO databases
- Accept player connections via Telnet
- Parse and execute commands
- Run verb code from the database
- Send output to players
- Handle multiple concurrent players
- Automatically checkpoint and recover from crashes

**Test Coverage:** 90 tests (85 passing, 5 flaky)  
**Commits:** 34

## Quick Start

```bash
# Install dependencies
mix deps.get

# Load a MOO database (optional)
# Place your .db file in /tmp/

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
- [Tasks](docs/tasks.md) - Task system and tick quotas
- [Checkpoint System](docs/checkpoint.md) - Automatic saves and recovery
- [Built-in Functions](docs/builtins-status.md) - Implementation status
- [Unicode Support](docs/unicode.md) - UTF-8 and grapheme handling
- [Network Configuration](docs/network-config.md) - Telnet/SSH/WebSocket setup
- [Database](docs/database.md) - Database format and operations
- [Ecosystem Guide](docs/ECOSYSTEM.md) - Overview of MOO cores and resources

## Configuration

All configuration is marked with `# CONFIG:` comments for easy extraction:

```elixir
# CONFIG: MOO world name (shown in banner and exports)
config :alchemoo, :moo_name, "MyMOO"

# CONFIG: Welcome text (shown in login banner if database doesn't provide one)
config :alchemoo, :welcome_text, "Welcome to our world!"

# CONFIG: Checkpoint settings
config :alchemoo, :checkpoint,
  dir: "/tmp/alchemoo/checkpoints",
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
- [x] Database parser (Format 1 & 4)
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

### Phase 2: Built-in Functions (24% Complete)
- [x] Critical built-ins (36/150)
  - [x] Output: notify, connected_players, connection_name
  - [x] Context: player, caller, this
  - [x] String: index, strsub, strcmp, explode
  - [x] Object: valid, parent, children, max_object
  - [x] Property: properties, property_info
  - [x] Plus 21 others (typeof, tostr, toint, etc.)
- [ ] Important built-ins (20-30 more)
  - [ ] Object: create, recycle, chparent, move
  - [ ] Property: add_property, delete_property, set_property_info
  - [ ] Verb: verbs, verb_info, add_verb, delete_verb
  - [ ] List: setadd, setremove, sort
- [ ] Nice-to-have built-ins (80-90 more)

### Phase 3: Polish & Enhancement
- [ ] Authentication system
- [ ] Object matching in commands
- [ ] Preposition validation
- [ ] Configuration extraction
- [ ] Performance optimization
- [ ] Fix flaky tests
- [ ] SSH support
- [ ] WebSocket support

## License

MIT
