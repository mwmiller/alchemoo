# Getting Started with Alchemoo

This guide will help you get Alchemoo up and running in minutes.

## Prerequisites

- Elixir 1.14+ and Erlang/OTP 25+
- A MOO database file (optional, but recommended)

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/alchemoo.git
cd alchemoo

# Install dependencies
mix deps.get

# Compile
mix compile
```

## Getting a MOO Database

Alchemoo works best with an existing MOO database. Here are some options:

### LambdaCore (Recommended for beginners)

LambdaCore is the classic MOO database, perfect for learning:

```bash
# Download LambdaCore
curl -o tmp/LambdaCore-12Apr99.db \
  https://github.com/SevenEcks/LambdaMOO/raw/master/LambdaCore-12Apr99.db
```

### JHCore (More features)

JHCore is a more modern MOO database with additional features:

```bash
# Download JHCore
curl -o tmp/JHCore-DEV-2.db \
  https://github.com/SevenEcks/lambda-moo-programming/raw/master/databases/JHCore-DEV-2.db
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
[info] Database loaded: 95 objects, 1699 verbs
[info] Checkpoint server started
[info] Telnet server listening on port 7777
```

## Connecting to the Server

Open a new terminal and connect via Telnet:

```bash
telnet localhost 7777
```

You should see a welcome message and a prompt:

```
Welcome to Alchemoo!
Connected as Wizard (#2)
> 
```

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

## Understanding the System

### Objects

Everything in a MOO is an object. Objects have:
- **Properties** - Data stored on the object
- **Verbs** - Code that can be executed
- **Parent** - Inheritance relationship
- **Location** - Where the object is

### Verbs

Verbs are pieces of MOO code attached to objects. When you type a command, Alchemoo:

1. Parses the command
2. Finds the matching verb
3. Executes the verb code
4. Sends output back to you

### Tasks

Each command spawns a task that executes the verb code. Tasks have:
- **Tick quota** - Maximum operations (default: 10,000)
- **Context** - player, this, caller
- **Environment** - Variables like verb, args, dobj, etc.

## Configuration

Alchemoo uses sensible defaults, but you can customize:

### Checkpoint Settings

```elixir
# config/config.exs
config :alchemoo, :base_dir, "tmp"

config :alchemoo, :checkpoint,
  interval: 300_000,  # 5 minutes
  keep_last: 5
```

### Network Settings

```elixir
config :alchemoo, :network,
  telnet: %{enabled: true, port: 7777},
  ssh: %{enabled: false, port: 2222}
```

### Task Limits

```elixir
config :alchemoo, :default_tick_quota, 10_000
config :alchemoo, :max_tasks_per_player, 10
```

## Development Workflow

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/alchemoo/command/parser_test.exs

# Run tests with coverage
mix test --cover
```

### Running Demos

```bash
# Database demo
elixir examples/database_server_demo.exs

# Task demo
elixir examples/task_demo.exs

# Command demo
elixir examples/command_demo.exs
```

### Debugging

Start the server with IEx for interactive debugging:

```elixir
# Start server
iex -S mix

# Check database stats
Alchemoo.Database.Server.stats()

# List running tasks
Alchemoo.TaskSupervisor.list_tasks()

# Get object
Alchemoo.Database.Server.get_object(2)
```

## Common Issues

### Port Already in Use

If port 7777 is already in use:

```elixir
# config/config.exs
config :alchemoo, :network,
  telnet: %{enabled: true, port: 8888}
```

### Database Not Loading

Make sure your database file is in the correct location:

```bash
# Check if file exists
ls -lh tmp/*.db

# Check file format
head -1 tmp/LambdaCore-12Apr99.db
# Should show: ** LambdaMOO Database, Format Version 4 **
```

### Connection Refused

Make sure the server is running:

```bash
# Check if server is listening
lsof -i :7777

# Or use netstat
netstat -an | grep 7777
```

## Next Steps

Now that you have Alchemoo running:

1. **Explore the database** - Use `@stats`, `@who`, and other commands
2. **Read the documentation** - Check out [docs/](docs/)
3. **Write MOO code** - Create verbs and properties
4. **Contribute** - Submit issues and pull requests!

## Resources

- [Commands Documentation](commands.md)
- [Built-in Functions](builtins-status.md)
- [Task System](tasks.md)
- [Checkpoint System](checkpoint.md)
- [Unicode Support](unicode.md)

## Getting Help

- **GitHub Issues** - Report bugs and request features
- **Discussions** - Ask questions and share ideas
- **Discord** - Join our community (coming soon!)

## License

MIT - See LICENSE file for details
