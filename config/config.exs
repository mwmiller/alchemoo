import Config

config :alchemoo, :base_dir, "tmp"

config :alchemoo, :network,
  telnet: %{enabled: true, port: 7777},
  ssh: %{enabled: false, port: 2222},
  websocket: %{enabled: false, port: 4000}

import_config "#{config_env()}.exs"
