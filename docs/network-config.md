# Alchemoo Network Configuration Examples

## Default Configuration (Hardcoded)

By default, Alchemoo starts with:
- Telnet: enabled on port 7777
- SSH: disabled
- WebSocket: disabled

## Future: config/config.exs

When configuration is extracted, you'll be able to configure like this:

```elixir
# config/config.exs
import Config

config :alchemoo,
  # Network listeners
  network: %{
    telnet: %{
      enabled: true,
      port: 7777
    },
    ssh: %{
      enabled: true,
      port: 2222
    },
    websocket: %{
      enabled: false,
      port: 4000
    }
  }
```

## Examples

### Telnet Only (Default)
```elixir
config :alchemoo,
  network: %{
    telnet: %{enabled: true, port: 7777},
    ssh: %{enabled: false},
    websocket: %{enabled: false}
  }
```

### Telnet + SSH
```elixir
config :alchemoo,
  network: %{
    telnet: %{enabled: true, port: 7777},
    ssh: %{enabled: true, port: 2222},
    websocket: %{enabled: false}
  }
```

### Custom Ports
```elixir
config :alchemoo,
  network: %{
    telnet: %{enabled: true, port: 8888},
    ssh: %{enabled: true, port: 9999},
    websocket: %{enabled: false}
  }
```

### SSH Only (No Telnet)
```elixir
config :alchemoo,
  network: %{
    telnet: %{enabled: false},
    ssh: %{
      enabled: true, 
      port: 2222,
      show_fingerprint: true  # Uses fingerart for drunken bishop display
    },
    websocket: %{enabled: false}
  }
```

### All Protocols
```elixir
config :alchemoo,
  network: %{
    telnet: %{enabled: true, port: 7777},
    ssh: %{enabled: true, port: 2222},
    websocket: %{enabled: true, port: 4000}
  }
```

## Environment Variables (Future)

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :alchemoo,
    network: %{
      telnet: %{
        enabled: System.get_env("ALCHEMOO_TELNET_ENABLED", "true") == "true",
        port: String.to_integer(System.get_env("ALCHEMOO_TELNET_PORT", "7777"))
      },
      ssh: %{
        enabled: System.get_env("ALCHEMOO_SSH_ENABLED", "false") == "true",
        port: String.to_integer(System.get_env("ALCHEMOO_SSH_PORT", "2222"))
      }
    }
end
```

## Checking Active Listeners

```elixir
# In IEx
iex> Alchemoo.Network.Supervisor.listeners()
[
  %{id: Alchemoo.Network.Telnet, pid: #PID<0.123.0>, active: true}
]

iex> Alchemoo.Network.Telnet.info()
%{ip: "0.0.0.0", port: 7777, connections: 2}
```

## Implementation Status

- ✅ Telnet (implemented)
- ⏳ SSH (placeholder ready, needs implementation)
  - Will use `fingerart` package for drunken bishop fingerprint display
  - See `lib/alchemoo/network/ssh.ex` for implementation notes
- ⏳ WebSocket (not yet implemented)

## Dependencies

- **Telnet**: `:ranch` (included)
- **SSH**: `:ssh` (built-in Erlang) + `:fingerart` (optional, for fingerprint display)
- **WebSocket**: TBD (likely Phoenix.Socket or Cowboy)

## Notes

- Each listener runs independently
- Listeners can be enabled/disabled without affecting others
- Port conflicts will cause startup failure (by design)
- All listeners share the same Connection.Supervisor
