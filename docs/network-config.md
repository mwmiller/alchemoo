# Alchemoo Network Configuration

Alchemoo supports multiple network transports, all managed through a unified connection layer.

## Configuration

All network settings are managed in `config/config.exs`:

```elixir
# config/config.exs
config :alchemoo, :network,
  telnet: %{
    enabled: true,
    port: 7777
  },
  ssh: %{
    enabled: true,
    port: 2222,
    # Optional: custom host key directory
    system_dir: "/path/to/ssh/keys"
  },
  websocket: %{
    enabled: true,
    port: 4444
  }
```

## Supported Transports

### Telnet (Port 7777)
The classic MOO transport. Uses `:ranch` for high-performance TCP handling.
- ✅ Standard Telnet protocol
- ✅ Terminal type negotiation
- ✅ Window size negotiation (NAWS)
- ✅ Character-at-a-time mode support

### SSH (Port 2222)
Modern secure transport with advanced features.
- ✅ Public Key Authentication
- ✅ Password Authentication (mapped to character login)
- ✅ Automated Key Registration (first login with key)
- ✅ **Visual Fingerprints**: Uses `fingerart` (drunken bishop) for key verification
- ✅ **Interactive Readline**: Built-in line editing, history, and ANSI support

### WebSocket (Port 4444)
Modern web-based client access.
- ✅ **High Performance**: Powered by Bandit and WebSock.
- ✅ **Standard Subprotocols**: Supports `plain.mudstandards.org`.
- ✅ **Bi-directional**: Full support for all MOO commands and output.

## Examples

### Telnet Only
```elixir
config :alchemoo, :network,
  telnet: %{enabled: true, port: 7777},
  ssh: %{enabled: false},
  websocket: %{enabled: false}
```

### SSH Only (Secure Mode)
```elixir
config :alchemoo, :network,
  telnet: %{enabled: false},
  ssh: %{enabled: true, port: 2222},
  websocket: %{enabled: false}
```

## Checking Active Listeners

You can inspect active listeners from IEx:

```elixir
iex> Alchemoo.Network.Supervisor.listeners()
[
  {Alchemoo.Network.Telnet, #PID<0.123.0>},
  {Alchemoo.Network.SSH, #PID<0.124.0>}
]
```

## Implementation Details

### SSH Fingerprints
Alchemoo uses the `fingerart` library to generate "Drunken Bishop" visualizations of SSH public keys. This allows users to easily verify their keys visually:

```
+--[RSA 4096]----+
|      .oo.       |
|      .o.o       |
|     .  o o      |
|      .. o .     |
|     .  S .      |
|    . .  .       |
|     . .         |
|      .          |
|                 |
+----[SHA256]-----+
```

### Unified Connection Handler
Regardless of the transport (Telnet or SSH), all connections are handled by `Alchemoo.Connection.Handler`. This ensures consistent command parsing, verb execution, and output handling across all protocols.

---

**This documentation is up to date as of March 1, 2026.**
