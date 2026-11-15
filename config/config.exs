import Config

config :rock,
  start_server: true,
  port: 4000

import_config "#{config_env()}.exs"

