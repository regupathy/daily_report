defmodule DailyReport.SqlWorkPoolSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start() do
    username = Application.fetch_env!(:daily_report, :db_username)
    password = Application.fetch_env!(:daily_report, :db_password)
    database = Application.fetch_env!(:daily_report, :db_database)
    dbconfig = [username: username, password: password, database: database]
    spec = {MyXQL, dbconfig}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop(ref) do
    DynamicSupervisor.terminate_child(__MODULE__, ref)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: []
    )
  end
end
