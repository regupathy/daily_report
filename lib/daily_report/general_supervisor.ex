defmodule DailyReport.GeneralSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {CurrencyRates, []},
      # {WorkScheduler, []},
      {WorkManager,[]},
      {AppNodeManager, []}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
