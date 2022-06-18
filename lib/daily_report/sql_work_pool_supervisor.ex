defmodule DailyReport.SqlWorkPoolSupervisor do

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end 
  
  def start() do
    spec = {MyXQL, []}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop(ref) do
    DynamicSupervisor.terminate_child(__MODULE__, ref)
  end

  @impl true
  def init(init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [init_arg]
    )
  end


end
