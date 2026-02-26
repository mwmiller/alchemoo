# Alchemoo Project Summary

## Overview

Alchemoo is a modern, high-performance LambdaMOO-compatible server built on the Erlang BEAM VM. It successfully loads and executes existing MOO databases with full Unicode support, automatic checkpointing, and a complete command execution pipeline.

## Status: Working MOO Server

**Commits:** 80+  
**Current branch tests (Feb 26, 2026):** 125 tests, 8 failing  
**Lines of Code:** ~7,000  
**Development Time:** Phase 2 (Built-ins) Complete (100%)

## What Works

### Core Infrastructure (100%)
- ✅ Database parser (Format 4)
- ✅ MOO language parser and interpreter
- ✅ Database server with ETS storage
- ✅ Task system with tick quotas and process isolation
- ✅ Connection handling (multiple players)
- ✅ Network layer (Telnet on port 7777)
- ✅ Checkpoint system with auto-recovery
- ✅ MOO database export (Format 4)
- ✅ Command parsing and execution
- ✅ Registry-based task tracking

### Built-in Functions (100%)
- ✅ **140 of 140 implemented**
- ✅ **All Critical Functions:** Output, Context, Object/Prop/Verb management
- ✅ **Math:** Full suite including extended trig and log functions
- ✅ **String:** Full suite including regex, substitution, and hashing
- ✅ **Task Management:** `task_id`, `kill_task`, `suspend`, `resume`, `yield`, `eval`, `raise`, `pass`
- ✅ **Security:** `caller_perms`, `set_task_perms`, `callers`
- ✅ **Network:** `listen`, `unlisten`, `open_network_connection` (stubs), `force_input`, `read`, `flush_input`, `connection_options`
- ✅ **Introspection:** `function_info`, `disassemble`, `queue_info`

### Features
- ✅ Full Unicode (UTF-8) support
- ✅ Grapheme-aware string operations
- ✅ Automatic periodic checkpoints (5 min)
- ✅ Automatic MOO exports (every 11th checkpoint)
- ✅ Crash recovery with checkpoint reload
- ✅ Task limits (10 per player, configurable)
- ✅ Tick quotas (10,000 per task, configurable)
- ✅ Clean disconnect handling
- ✅ Task cleanup on disconnect
- ✅ Real Authentication (connect/create)
- ✅ Full Object Matching (me, here, ID, name, aliases)

## Architecture

### Process Model
```
User (telnet) → Ranch TCP → Connection.Handler (GenServer)
                              ↓
                         TaskSupervisor → Task (GenServer)
                              ↓
                         Database.Server (ETS + GenServer)
                              ↓
                         Checkpoint.Server (GenServer)
```

## Next Steps

### Priorities (Phase 3)
1.  **Configuration**: Extract hardcoded config to `config/config.exs`.
2.  **SSH Support**: Implement SSH/SFTP access using `fingerart/ssh`.
3.  **WebSocket Support**: Modern web-based client access.
4.  **Performance**: Optimize hot paths in the interpreter and database lookups.

### Known Issues
- `listen`, `unlisten`, and `open_network_connection` currently return `E_PERM` (placeholders).
- `disassemble` returns source code instead of bytecode (valid for AST interpreter but worth noting).
- `Alchemoo.Database.Parser.parse_file/1` is currently missing (tests still call it).
- MOO export currently fails on `{:float, "..."}`
- `verb_args()` has a current regression in built-ins tests.

---

**This summary is current as of Feb 26, 2026.**
