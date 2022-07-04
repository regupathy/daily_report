defmodule WorkState do
  use GenServer
  require Logger

  def start_link(jobName, workStatus) do
    GenServer.start_link(__MODULE__, [jobName, workStatus])
  end

  # ------------------------------------------------------------------------------
  #                 API 
  # ------------------------------------------------------------------------------

  def reassign(jobName,jobId,fromNode,toNode)do
    send_all(jobName,{:reassign, jobId,fromNode,toNode})  
  end

  def update_status(jobName, status) do
    send_all(jobName,{:update_status, status})
  end

  def job_completed(jobName, jobID) do
    send_all(jobName,{:work_completed, jobID})
  end

  def print(jobName) do
    GenServer.cast({get_process_name(jobName), node()}, :print)
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
  def handle_cast({:update_status, status}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.update_status(status, workStatus)
    {:noreply, %{state | work_status: newStatus}}
  end

  def handle_cast({:work_completed, jobId}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.job_complete(jobId, workStatus)
    isCompleted = NodeWorkStatus.isAllCompleted?(newStatus)
    if isCompleted do
      WorkManager.all_done()
    end
    {:noreply, %{state | work_status: newStatus}}
  end


  def handle_cast({:reassign, jobId,fromNode,toNode}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.reassign(workStatus,jobId,fromNode,toNode)
    {:noreply, %{state | work_status: newStatus}}
  end

  def handle_cast(:print,%{work_status: workStatus} = state) do
    NodeWorkStatus.print_state(workStatus)
    {:noreply,state}
  end

  defp get_process_name(jobName) do
    String.to_existing_atom(jobName <> @name_suffix)
  end

  defp send_all(jobName,message)do
    for node <- :erlang.nodes() ++ [node()],
        do: {get_process_name(jobName), node} |> GenServer.cast(message)  
  end

end
