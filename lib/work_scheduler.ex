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
    {:ok, %{master: false, nodes: [], on_process: false, master_ref: nil, handlers: []}}
  end

  # ------------------------------------------------------------------------------
  #                  Communication between global App Node Manager
  # ------------------------------------------------------------------------------
  @impl true
  def handle_call(:be_master, from, state) do
    {:reply, :ok, %{state | master: true}}
  end

  @doc """
      App Node Manager initiate work to master WorkScheduler
  """
  def handle_call({:begin_work, nodes}, _from, %{master: true} = state) do
    works = nodes |> Stream.cycle() |> Enum.zip(Work.get_all_work_names())
    schedule = for {node, work_name} <- works, do: {make_ref, node, work_name}
    workStatus = NodeWorkStatus.new(schedule)
    inform_peers(%{work_status: workStatus, nodes: nodes}, nodes)
    {:reply, :ok, state}
  end

  @doc """
      scheduler checking the incomplete jobs of down nodes and reassign it remainig available nodes
  """
  def handle_call({:check_work, nodes}, _from, %{master: true, nodes: usednodes} = state)
      when length(nodes) == length(usednodes) do
    {:reply, :ok, state}
  end

  def handle_call(
        {:check_work, nodes},
        _from,
        %{master: true, nodes: usednodes, status: status} = state
      ) do
    pending = NodeWorkStatus.get_incomplete_jobs(usednodes -- nodes, status)

    if pending != [] do
      reassign = nodes |> Stream.cycle() |> Enum.zip(pending)
      inform_peers(%{reassign_work: reassign, nodes: nodes}, nodes)
    end

    {:reply, :ok, state}
  end

  # -----------------------------------------------------------------------------------
  #       Communication between Schedulers
  # -----------------------------------------------------------------------------------
  @doc """
      All Schedulers will begin their work 
  """
  @impl true
  def handle_cast(%{work_status: workStatus, nodes: nodes}, state) do
    handlers =
      for {id, job_name, row} <- NodeWorkStatus.get_jobs(node(), workStatus) do
        {:ok, ref} = DailyReport.AppWorkSupervisor.start_work(id, job_name, row)
        ref
      end

    {:noreply,
     %{state | work_status: workStatus, nodes: nodes, on_process: true, handlers: handlers}}
  end

  @doc """
       Schedulers create a new handler if any job assinged to his node
  """
  @impl true
  def handle_cast(
        %{reassign_work: reassign, nodes: nodes},
        %{handlers: handlers, work_status: workStatus} = state
      ) do
    {ids, newWorkStatus} = NodeWorkStatus.reassign(reassign, node(), workStatus)

    newhandlers =
      for {id, job_name, row} <- NodeWorkStatus.get_jobs(ids, node(), newWorkStatus) do
        {:ok, ref} = DailyReport.AppWorkSupervisor.start_work(id, job_name, row)
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

  @doc """
      Scheduler inform other scheduler about job status
  """
  def handle_cast({:update, status}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.update_status(status, workStatus)
    {:noreply, %{state | work_status: newStatus}}
  end

  @doc """
  Scheduler inform to other scheduler when handler job is completed
  """
  def handle_cast({:completed, job}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.job_complete(job, workStatus)
    {:noreply, %{state | work_status: newStatus}}
  end

  @doc """
  Scheduler inform to other scheduler when all jobs are completed
  """
  def handle_cast({:node_completed_jobs, node}, %{nodes: nodes} = state) do
    pendingNodes = nodes -- [node]
    # checking the master scheduler whether all nodes are done their jobs
    # if all done mean it will inform the global app node manager that all jobs are completed
    if pendingNodes == [] and state.master do
      :global.send(AppNodeManager, {:work_done, self})
    end

    {:noreply, %{state | nodes: pendingNodes}}
  end

  # ----------------------------------------------------------------------------
  #       Communication between Handlers
  # ----------------------------------------------------------------------------
  @doc """
      Own Handler inform his schedular about his status 
  """
  @impl true
  def handle_info(
        {:work_update, status, handler},
        %{nodes: nodes, handlers: handlers, work_status: workStatus} = state
      ) do
    if handler in handlers do
      newStatus = NodeWorkStatus.update_status(status, workStatus)
      inform_peers({:update, status}, nodes -- [node])
      {:noreply, %{state | work_status: newStatus}}
    else
      {:noreply, state}
    end
  end

  @doc """
  Own handler inform his scheduler when job is completed
  """
  def handle_info(
        {:done, job, handler},
        %{nodes: nodes, handlers: handlers, work_status: workStatus} = state
      ) do
    newStatus = NodeWorkStatus.job_complete(job, workStatus)
    inform_peers({:completed, job}, nodes -- [node])
    DailyReport.AppWorkSupervisor.stop(handler)
    newhandlers = handlers -- [handler]

    if newhandlers == [] do
      inform_peers({:node_completed_jobs, node()}, nodes -- [node()])
      {:noreply, %{state | work_status: newStatus, handlers: newhandlers, on_process: false}}
    else
      {:noreply, %{state | work_status: newStatus, handlers: newhandlers}}
    end
  end

  defp inform_peers(msg, nodes),
    do: for(node <- nodes, do: {node, __MODULE__} |> GenServer.cast(msg))
end
