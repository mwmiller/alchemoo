# Getting Started with Alchemoo

This guide will help you get Alchemoo up and running in minutes.

## Prerequisites

- Elixir 1.14+ and Erlang/OTP 25+
- A MOO database file (optional, but recommended)

## Installation

```bash
# Clone the repository
git clone https://github.com/mwmiller/alchemoo.git
cd alchemoo

# Install dependencies
mix deps.get

# Compile
mix compile
```

## Getting a MOO Database

Alchemoo works best with an existing MOO database. By default, it includes a fixture for testing, but for a real world, you should get a standard core.

### LambdaCore (Recommended for beginners)

LambdaCore is the classic MOO database, perfect for learning:

```bash
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$STATE_HOME/alchemoo"

# Download LambdaCore
curl -o "$STATE_HOME/alchemoo/LambdaCore-12Apr99.db" \
  https://github.com/SevenEcks/LambdaMOO/raw/master/LambdaCore-12Apr99.db
```

## Starting the Server

```bash
# Start the server
mix run --no-halt

# Or start with IEx for interactive development
iex -S mix
```

You should see output like:

```
[info] Startup database loaded from test/fixtures/lambdacore.db (95 objects)
[info] Checkpoint server started (dir: /Users/matt/.local/state/alchemoo/checkpoints, ...)
[info] Telnet server listening on port 7777
[info] SSH server listening on port 2222
```

## Connecting to the Server

### Via Telnet (Classic)

```bash
telnet localhost 7777
```

### Via SSH (Modern & Secure)

Alchemoo features a full SSH implementation with public key support and interactive readline.

```bash
ssh localhost -p 2222
```

On your first connection with a public key, Alchemoo will offer to register your key to your character.

## Your First Commands

Try these commands to get started:

```
> look
You see nothing special.

> @who
Connected players:
  You

> @stats
Database: 95 objects
Tasks: 0

> quit
Goodbye!
```

## Configuration

Alchemoo uses `config/config.exs` for all settings:

### Network Settings

```elixir
config :alchemoo, :network,
  telnet: %{enabled: true, port: 7777},
  ssh: %{enabled: true, port: 2222}
```

### Checkpoint Settings

```elixir
config :alchemoo, :checkpoint,
  interval: 307_000,  # 5 minutes (prime)
  keep_last: 23
```

## Next Steps

1. **Explore the database** - Use `@stats`, `@who`, and other commands
2. **Read the documentation** - Check out [docs/](docs/)
3. **Write MOO code** - Create verbs and properties

---

**This documentation is up to date as of March 1, 2026.**
