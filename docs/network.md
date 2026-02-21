# Alchemoo Network Demo

This demonstrates the complete network stack.

## Start the Server

```bash
iex -S mix
```

The server will start on port 7777.

## Connect via Telnet

```bash
telnet localhost 7777
```

Or use netcat:

```bash
nc localhost 7777
```

## Commands

Once connected:

```
connect wizard test
@stats
@who
quit
```

## Architecture

```
TCP Connection (port 7777)
  ↓
Ranch Listener
  ↓
Connection.Handler (GenServer)
  ↓
Task.Supervisor → Task (GenServer)
  ↓
Database.Server (ETS + GenServer)
```

## Features

- ✅ Telnet server on port 7777
- ✅ Connection handler per player
- ✅ Input buffering
- ✅ Output queuing
- ✅ Basic commands (@stats, @who, quit)
- ✅ Task spawning (ready)
- ✅ Database access

## Next Steps

- Implement actual MOO command execution
- Add authentication
- Add player creation
- Implement notify() built-in
- Add more @ commands
