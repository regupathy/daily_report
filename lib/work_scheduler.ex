defmodule WorkScheduler do
  use GenServer

  @moduledoc """
    Work Scheduler is responsible for maintain 
              1. share all work meta data in all nodes
              2. share the live working csv file updates into all nodes
              3. save live status of all node's work status 
  """
  @impl true
  def init(_opts) do
    Work.init()
    {:ok, %{master: false, nodes: [], on_process: false, master_ref: nil, handlers: []}}
  end

  # ------------------------------------------------------------------------------
  #                 API only for AppNodeManager
  # ------------------------------------------------------------------------------

  def markAsMaster() do
    GenServer.call(WorkScheduler, :be_master)
  end

  def start_work(name,nodes) do
    GenServer.call(WorkScheduler, {:begin_work, nodes,name})
  end

  def rebalance_work(name,nodes) do
    GenServer.call(WorkScheduler, {:rebalance_work,name,nodes})
  end

  # ------------------------------------------------------------------------------
  #                  Communication between global App Node Manager
  # ------------------------------------------------------------------------------
  @impl true
  def handle_call(:be_master, _from, state) do
    {:reply, :ok, %{state | master: true}}
  end

  @doc """
      App Node Manager initiate work to master WorkScheduler
  """
  def handle_call({:begin_work, nodes,workname}, _from, %{master: true} = state) do
    works = nodes |> Stream.cycle() |> Enum.zip(Work.get_all_work_names())
    schedule = for {node, work_name} <- works, do: {make_ref(), node, work_name}
    workStatus = NodeWorkStatus.new(schedule)
    inform_all({:work_begin,%{work_status: workStatus, nodes: nodes,workname: workname}}, nodes)
    {:reply, :ok, state}
  end

  
  # Scheduler checking the incomplete jobs of down nodes and reassign it remainig available nodes
  def handle_call({:check_work, nodes}, _from, %{master: true, nodes: usednodes} = state)
      when length(nodes) == length(usednodes) do
    {:reply, :ok, state}
  end

  def handle_call(
        {:rebalance_work, workname, nodes},
        _from,
        %{master: true, nodes: usednodes, status: status} = state
      ) do
    pending = NodeWorkStatus.get_incomplete_jobs(usednodes -- nodes, status)

    if pending != [] do
      reassign = nodes |> Stream.cycle() |> Enum.zip(pending)
      inform_all({:reassign_work, workname,%{reassign_work: reassign, nodes: nodes}}, nodes)
    end

    {:reply, :ok, state}
  end

  # -----------------------------------------------------------------------------------
  #       Communication between Schedulers
  # -----------------------------------------------------------------------------------

  #  All Schedulers will begin their work 
  @impl true
  def handle_cast({:work_begin,%{work_status: workStatus, nodes: nodes, workname: workname}}, state) do
    destination = Path.join("output",workname)
    File.mkdir(destination)
    handlers =
      for {id, job_name, row} <- NodeWorkStatus.get_jobs(node(), workStatus) do
        {:ok, ref} =
          WorkHandler.params(id, job_name, row,destination) |> DailyReport.AppWorkSupervisor.start_work()

        ref
      end

    {:noreply,
     %{state | work_status: workStatus, nodes: nodes, on_process: true, handlers: handlers}}
  end

  # Schedulers create a new handler if any job assinged to his node
  def handle_cast(
        {:reassign_work ,workname,%{reassign_work: reassign, nodes: nodes}},
        %{handlers: handlers, work_status: workStatus} = state
      ) do
        destination = Path.join("output",workname)
        File.mkdir(destination)
    newWorkStatus = NodeWorkStatus.reassign(reassign, workStatus)

    newhandlers =
      for {id, job_name, row} <- NodeWorkStatus.get_jobs(reassign, node(), newWorkStatus) do
        {:ok, ref} =
          WorkHandler.params(id, job_name, row,destination) 
          |> DailyReport.AppWorkSupervisor.start_work()
        
        ref
      end

    {:noreply,
     %{
       state
       | work_status: newWorkStatus,
         nodes: nodes,
         on_process: true,
         handlers: handlers ++ newhandlers
     }}
  end

  # Scheduler inform other scheduler about job status
  def handle_cast({:update, status}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.update_status(status, workStatus)
    {:noreply, %{state | work_status: newStatus}}
  end

  # Scheduler inform to other scheduler when handler job is completed
  def handle_cast({:completed, job}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.job_complete(job, workStatus)
    {:noreply, %{state | work_status: newStatus}}
  end

  # Scheduler inform to other scheduler when all jobs are completed
  def handle_cast({:node_completed_jobs, node}, %{nodes: nodes} = state) do
    pendingNodes = nodes -- [node]
    # checking the master scheduler whether all nodes are done their jobs
    # if all done mean it will inform the global app node manager that all jobs are completed
    if pendingNodes == [] and state.master do
      AppNodeManager.to_global(:work_done)
    end
    {:noreply, %{state | nodes: pendingNodes}}
  end

  # ----------------------------------------------------------------------------
  #       Communication between Handlers
  # ----------------------------------------------------------------------------

  # Own Handler inform his schedular about his status 
  @impl true
  def handle_info(
        {:work_update, status, handler},
        %{nodes: nodes, handlers: handlers, work_status: workStatus} = state
      ) do
    if handler in handlers do
      newStatus = NodeWorkStatus.update_status(status, workStatus)
      inform_peers({:update, status}, nodes)
      {:noreply, %{state | work_status: newStatus}}
    else
      {:noreply, state}
    end
  end

  # Own handler inform his scheduler when job is completed
  def handle_info(
        {:done, handler},
        %{nodes: nodes, handlers: handlers} = state
      ) do
    DailyReport.AppWorkSupervisor.stop(handler)
    newhandlers = handlers -- [handler]
    if newhandlers == [] do
      inform_all({:node_completed_jobs, node()}, nodes)
    end
    {:noreply, %{state | handlers: newhandlers}}
  end

  defp inform_peers(msg, nodes) do
    nodes -- [node()] |> inform_all(msg)
  end

  defp inform_all(msg, nodes) do
    for(node <- nodes, do: {node, __MODULE__} |> GenServer.cast(msg))
  end

end
