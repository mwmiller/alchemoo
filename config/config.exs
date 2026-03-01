import Config

state_home = System.get_env("XDG_STATE_HOME") || Path.join(System.user_home!(), ".local/state")
config :alchemoo, :base_dir, Path.join(state_home, "alchemoo")

# CONFIG: Startup world (source MOO database file)
config :alchemoo, :core_db, "test/fixtures/lambdacore.db"

# CONFIG: MOO world name (shown in banner and exports)
config :alchemoo, :moo_name, "Alchemoo"

# CONFIG: Welcome text (shown in login banner if database doesn't provide one)
config :alchemoo, :welcome_text, "Welcome to Alchemoo!"

# CONFIG: Task limits
config :alchemoo,
  default_tick_quota: 10_000,
  system_tick_quota: 1_000_003,
  max_tasks_per_player: 10,
  max_total_tasks: 1000

# CONFIG: Connection limits
config :alchemoo, :max_connections, 1000

# CONFIG: Checkpoint settings
config :alchemoo, :checkpoint,
  # 307 seconds (prime)
  interval: 307_000,
  keep_last: 23,
  checkpoint_on_shutdown: true,
  moo_export_interval: 11,
  keep_last_moo_exports: 23

config :alchemoo, :network,
  telnet: %{enabled: true, port: 7777},
  ssh: %{enabled: true, port: 2222},
  websocket: %{enabled: false, port: 4000}

# Optional high-volume trace logging (off by default).
config :alchemoo,
  trace_builtins: false,
  trace_connections: false,
  trace_ssh: false,
  trace_runtime_verbs: false,
  trace_runtime_properties: false,
  trace_tasks: false,
  trace_output: true,
  trace_interpreter_eval: false,
  trace_interpreter_statements: false

import_config "#{config_env()}.exs"
