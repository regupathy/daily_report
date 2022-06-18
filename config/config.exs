import Config

# import_config "#{config_env()}.exs"

config :logger, :console,
 format: "[$level] $message $metadata\n",
 metadata: [:error_code, :file]

 