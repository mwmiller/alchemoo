import Config

state_home = System.get_env("XDG_STATE_HOME") || Path.join(System.user_home!(), ".local/state")
config :alchemoo, :base_dir, Path.join(state_home, "alchemoo")

config :alchemoo, :network,
  telnet: %{enabled: true, port: 7777},
  ssh: %{enabled: false, port: 2222},
  websocket: %{enabled: false, port: 4000}

import_config "#{config_env()}.exs"
