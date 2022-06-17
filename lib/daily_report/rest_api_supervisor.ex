defmodule DailyReport.RestAPISupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def enable_rest_api() do
    Supervisor.start_child(__MODULE__, [])
  end

  @impl true
  def init(_init_arg) do
    children = [
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: DailyDumbEndpoint,
        options: [port: 2000]
      )
    ]

    Supervisor.init(children, strategy: :simple_one_for_one)
  end
end
