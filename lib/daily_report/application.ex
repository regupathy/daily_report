defmodule DailyReport.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    dbconfig = [username: "root", name: :myxql, password: "password", database: "daily_updates"]

    children = [
      {MyXQL, dbconfig},
      {DailyReport.RestAPISupervisor, []},
      {DailyReport.SqlWorkPoolSupervisor, dbconfig},
      {DailyReport.AppWorkSupervisor, []}
    ]

    opts = [strategy: :one_for_all, name: DailyReport.Supervisor]
    Supervisor.start_link(children, opts)
  end
end


defp auto_join_nodes()do

end

