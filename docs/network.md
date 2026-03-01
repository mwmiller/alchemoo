# Alchemoo Network

Alchemoo supports multiple network transports, providing both traditional and modern ways to connect to the MOO.

## Supported Transports

### Telnet (Port 7777)
The classic way to connect to a MOO.
```bash
telnet localhost 7777
```
- **Local Echo**: Most telnet clients handle echoing characters locally.
- **Line Mode**: Typically sends a full line of text at once.

### SSH (Port 2222)
A modern, secure transport with advanced interactive features.
```bash
ssh wizard@localhost -p 2222
```
- **Readline Support**: Alchemoo implements a stateful line editor for SSH connections.
- **Interactive Editing**: Supports backspace, delete, home/end, and arrow-key navigation.
- **Command History**: Cycle through previous commands using Up/Down arrows.
- **ANSI Support**: Full support for ANSI escape sequences for text formatting and terminal control.
- **Automatic Authentication**: SSH public key authentication can be linked to MOO characters.

### WebSocket (Port 4444)
Modern web-based connection.
```bash
# Connect using a web client or websocat
websocat ws://localhost:4444
```
- **Browser Native**: Allows building web clients without Telnet proxies.
- **Bi-directional**: Supports standard MOO input and output.

## Architecture

```
User (Telnet/SSH/WS) 
      ↓
Transport Bridge (Ranch / :ssh / Bandit)
      ↓
Connection.Handler (GenServer)
      ↓
Task.Supervisor → Task (GenServer)
      ↓
Database.Server (ETS + GenServer)
```

Alchemoo uses a unified transport interface across all protocols. The `Connection.Handler` interacts with transports via a consistent API (`send/2`, `close/1`, `peername/1`, `use_readline?/0`, etc.).

## Configuration

Network settings are managed in `config/config.exs`:

```elixir
config :alchemoo, :network,
  telnet: %{
    enabled: true,
    port: 7777
  },
  ssh: %{
    enabled: true,
    port: 2222
  },
  websocket: %{
    enabled: true,
    port: 4444
  }
```

## Readline Implementation

For interactive connections (Telnet and SSH), Alchemoo uses a custom `Readline` module that processes input byte-by-byte. This allows the server to provide a rich CLI experience:

- **Buffer Management**: Edits happen in an in-memory buffer before being sent to the MOO.
- **Terminal Control**: Uses ANSI escape sequences to clear lines and reposition the cursor during editing.
- **History**: Maintains a per-connection history of recently executed commands.

---

**This documentation is up to date as of March 1, 2026.**
