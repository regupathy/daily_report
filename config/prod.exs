import Config

config :daily_report,
  openexchangerates_api_key: '23f7639edfb34aecbe04f8c94cea0671',
  db_username: "root",
  db_password: "password",
  db_database: "daily_updates"

config(:logger, :console,
  format: "[$level] $message $metadata\n",
  metadata: [:error_code, :file]
)
