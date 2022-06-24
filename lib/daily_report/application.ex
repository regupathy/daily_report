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
    {:ok, names} = :net_adm.names()
    localhost = :net_adm.localhost() |> List.to_string() |> String.split(".") |> hd

    for {node_name, _} <- names do
      true =
        (List.to_string(node_name) <> "@" <> localhost)
        |> String.to_atom()
        |> :net_kernel.connect_node()
    end
  end
end
