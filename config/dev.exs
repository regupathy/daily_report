import Config

config :daily_report,
  openexchangerates_api_key: :local,
  db_username: "root",
  db_password: "password",
  db_database: "daily_updates"

config :logger, :console,
  format: "[$level] $message $metadata\n",
  metadata: [:error_code, :file]
