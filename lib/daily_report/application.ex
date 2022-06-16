defmodule DailyReport.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: DailyDumb.Worker.start_link(arg)
      # {DailyDumb.Worker, arg}

      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: DailyDumbEndpoint,
        options: [port: 2000]
      ),
      {MyXQL, username: "root", name: :myxql, password: "password"}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DailyReport.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
