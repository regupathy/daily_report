defmodule DailyReport.AppWorkSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_work(id, work, row) do
    Supervisor.start_child(__MODULE__, [id, work, row])
  end

  def stop(ref) do
    Supervisor.delete_child(__MODULE__, ref)
  end

  @impl true
  def init(init_arg) do
    children = [
      {WorkHandler, []}
    ]

    Supervisor.init(children, strategy: :simple_one_for_one)
  end
end
