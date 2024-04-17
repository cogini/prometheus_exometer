import Config

config :logger,
  level: :info

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:pid, :module, :function, :line]

import_config "#{config_env()}.exs"
