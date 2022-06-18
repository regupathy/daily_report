defmodule DailyReport.RestAPISupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def enable_rest_api() do
    spec = Plug.Cowboy.child_spec(
      scheme: :http,
      plug: DailyReportEndpoint,
      options: [port: 2000]
    )
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init(init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [init_arg]
    )
  end

end
