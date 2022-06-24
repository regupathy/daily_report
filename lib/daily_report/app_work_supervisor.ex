defmodule DailyReport.AppWorkSupervisor do
  use DynamicSupervisor
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def stop(ref) do
    DynamicSupervisor.terminate_child(__MODULE__, ref)
  end

  def start_work(args) do
    spec = {WorkHandler, {args, self()}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: []
    )
  end
end
