import Config

config :daily_report,
  openexchangerates_api_key: :local,
  db_host: "localhost",
  db_port: 3306,
  db_username: "root",
  db_password: "password",
  db_database: "daily_updates"

config :logger, :console,
  format: "[$level] $message \n",
  metadata: [:error_code, :file]
