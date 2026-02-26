import Config

state_home = System.get_env("XDG_STATE_HOME") || Path.join(System.user_home!(), ".local/state")
config :alchemoo, :base_dir, Path.join(state_home, "alchemoo")

config :alchemoo, :network,
  telnet: %{enabled: true, port: 7777},
  ssh: %{enabled: false, port: 2222},
  websocket: %{enabled: false, port: 4000}

# Optional high-volume trace logging (off by default).
config :alchemoo,
  trace_builtins: false,
  trace_connections: false,
  trace_runtime_verbs: false,
  trace_runtime_properties: false,
  trace_tasks: false,
  trace_interpreter_eval: false

import_config "#{config_env()}.exs"
