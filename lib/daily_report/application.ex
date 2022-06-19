defmodule DailyReport.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    
    children = [
      {DailyReport.RestAPISupervisor, []},
      {DailyReport.SqlWorkPoolSupervisor, []},
      {DailyReport.AppWorkSupervisor, []},
      {DailyReport.GeneralSupervisor, []}
    ]

    auto_join_nodes()
    opts = [strategy: :one_for_one, name: DailyReport.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp auto_join_nodes() do

  end
  
end
