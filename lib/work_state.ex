defmodule WorkState do
  use GenServer
  require Logger

  def start_link(jobName, workStatus) do
    GenServer.start_link(__MODULE__, [jobName, workStatus])
  end

  # ------------------------------------------------------------------------------
  #                 API 
  # ------------------------------------------------------------------------------

  def update_status(jobName, status) do
    for node <- :erlang.nodes(),
        do: {get_process_name(jobName), node} |> GenServer.cast({:update_status, status})
  end

  def job_completed(jobName, jobID) do
    for node <- :erlang.nodes(),
        do: {get_process_name(jobName), node} |> GenServer.cast({:work_completed, jobID})
  end

  def get_my_job(jobName) do
    GenServer.call({get_process_name(jobName), node()}, {:get_job, node()})
  end

  def get_busy_nodes(jobName) do
    GenServer.call({get_process_name(jobName), node()}, :get_busy_nodes)
  end

  # ------------------------------------------------------------------------------
  #                 GenServer CallBacks
  # ------------------------------------------------------------------------------

  @name_suffix "_WorkState"
  @impl true
  def init([jobName, workStatus]) do
    Process.flag(:trap_exit, true)
    name = String.to_atom(jobName <> @name_suffix)
    Process.register(self(), name)
    {:ok, %{work_status: workStatus}}
  end

  @impl true
  def handle_call({:get_job, node}, _, %{work_status: workStatus} = state) do
    {:reply, NodeWorkStatus.get_jobs(node, workStatus), state}
  end

  def handle_call(:get_busy_nodes, _from, %{work_status: workStatus} = state) do
    busyNodes = NodeWorkStatus.get_incomplete_jobs(workStatus)
    {:reply, busyNodes, state}
  end

  @impl true
  def handle_cast({:update, status}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.update_status(status, workStatus)
    {:noreply, %{state | work_status: newStatus}}
  end

  def handle_cast({:completed, job}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.job_complete(job, workStatus)
    {:noreply, %{state | work_status: newStatus}}
  end

  defp get_process_name(jobName) do
    String.to_existing_atom(jobName <> @name_suffix)
  end
end
