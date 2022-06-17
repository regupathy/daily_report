defmodule DailyReport.SqlWorkPoolSupervisor do
    use Supervisor
  
    def start_link(init_arg) do
      Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    end
  
    def start() do
      Supervisor.start_child(__MODULE__, [])
    end
  
    @impl true
    def init(init_arg) do
      children = [
      %{ id: SqlWorker,start: {MyXQL,:start_link,[init_arg]}}
      ]
      Supervisor.init(children, strategy: :simple_one_for_one)
    end
  end



