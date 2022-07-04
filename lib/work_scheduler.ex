defmodule WorkScheduler do
  use GenServer
  require Logger

  @moduledoc """
    Work Scheduler is responsible for maintain 
              1. share all work meta data in all nodes
              2. share the live working csv file updates into all nodes
              3. save live status of all node's work status 
  """

  defstruct [:master, :nodes, :working_nodes, :work_status, :on_process, :master_ref, :handlers]

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :erlang.process_flag(:trap_exit, true)
    Work.init()

    {:ok,
     %WorkScheduler{master: false, nodes: [], on_process: false, master_ref: nil, handlers: []}}
  end

  # ------------------------------------------------------------------------------
  #                 API only for AppNodeManager
  # ------------------------------------------------------------------------------

  def markAsMaster() do
    GenServer.call(WorkScheduler, :be_master)
  end

  def start_work(name, nodes) do
    GenServer.call(WorkScheduler, {:begin_work, nodes, name})
  end

  def rebalance_work(name, nodes) do
    GenServer.call(WorkScheduler, {:rebalance_work, name, nodes})
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
  def handle_call({:begin_work, nodes, workname}, _from, %{master: true} = state) do
    works = nodes |> Stream.cycle() |> Enum.zip(Work.get_all_work_names())
    Logger.info("Work Distribution is started ~n #{inspect(works)}")
    schedule = for {node, work_name} <- works, do: {make_ref(), node, work_name}
    workStatus = NodeWorkStatus.new(schedule)
    Logger.info("Work Schedule is : #{inspect(workStatus)}")
    inform_all({:work_begin, %{work_status: workStatus, nodes: nodes, workname: workname}}, nodes)
    {:reply, :ok, state}
  end

  # Scheduler checking the incomplete jobs of down nodes and reassign it remainig available nodes
  def handle_call({:rebalance_work, nodes}, _from, %{master: true, nodes: usednodes} = state)
      when length(nodes) == length(usednodes) do
    {:reply, :ok, state}
  end

  def handle_call(
        {:rebalance_work, workname, nodes},
        _from,
        %{master: true, working_nodes: usednodes, work_status: status} = state
      ) do
    pending = NodeWorkStatus.get_incomplete_jobs(usednodes -- nodes, status)

    if pending != [] do
      Logger.info(" Schedule rebalancing the work : #{inspect(pending)}")
      reassign = nodes |> Stream.cycle() |> Enum.zip(pending)
      inform_all({:reassign_work, workname, %{reassign_work: reassign, nodes: nodes}}, nodes)
    end

    {:reply, :ok, state}
  end

  # -----------------------------------------------------------------------------------
  #       Communication between Schedulers
  # -----------------------------------------------------------------------------------

  #  All Schedulers will begin their work 
  @impl true
  def handle_cast(
        {:work_begin, %{work_status: workStatus, nodes: nodes, workname: workname}},
        state
      ) do
    destination = Path.join("output", workname)
    File.mkdir(destination)
    # destination = destination |>  Path.expand(__DIR__)
    Logger.info("Scheduler start work and use directory #{destination}")

    handlers =
      for {id, job_name, row} <- NodeWorkStatus.get_jobs(node(), workStatus) do
        {:ok, ref} =
          WorkHandler.params(id, job_name, workname,row, destination)
          |> DailyReport.AppWorkSupervisor.start_work()

        ref
      end

    Logger.info("Handlers created for #{workname} are #{inspect(handlers)}")

    {:noreply,
     %{
       state
       | work_status: workStatus,
         working_nodes: nodes,
         on_process: true,
         handlers: handlers
     }}
  end

  # Schedulers create a new handler if any job assinged to his node
  def handle_cast(
        {:reassign_work, workname, %{reassign_work: reassign, nodes: nodes}},
        %{handlers: handlers, work_status: workStatus} = state
      ) do
    destination = Path.join("output", workname)
    File.mkdir(destination)
    newWorkStatus = NodeWorkStatus.reassign(reassign, workStatus)
    Logger.info(" new work status : #{inspect(newWorkStatus)}")

    newhandlers =
      for {id, job_name, row} <- NodeWorkStatus.get_jobs(node(), newWorkStatus) do
        {:ok, ref} =
          WorkHandler.params(id, job_name, workname,row, destination)
          |> DailyReport.AppWorkSupervisor.start_work()

        Logger.info("Handlers created for #{job_name} are #{inspect(ref)}")
        ref
      end

    {:noreply,
     %{
       state
       | work_status: Map.merge(workStatus, newWorkStatus),
         nodes: nodes,
         on_process: true,
         handlers: handlers ++ newhandlers
     }}
  end

  # Scheduler inform other scheduler about job status
  def handle_cast({:update, status}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.update_status(status, workStatus)
    # Logger.info(" others status #{inspect(status)} and new : #{inspect(newStatus)}")
    {:noreply, %{state | work_status: newStatus}}
  end

  # Scheduler inform to other scheduler when handler job is completed
  def handle_cast({:completed, job}, %{work_status: workStatus} = state) do
    newStatus = NodeWorkStatus.job_complete(job, workStatus)
    {:noreply, %{state | work_status: newStatus}}
  end

  # Scheduler inform to other scheduler when all jobs are completed
  def handle_cast({:node_completed_jobs, node}, %{working_nodes: nodes} = state) do
    pendingNodes = nodes -- [node]
    # checking the master scheduler whether all nodes are done their jobs
    # if all done mean it will inform the global app node manager that all jobs are completed
    if pendingNodes == [] and state.master do
      AppNodeManager.to_global(:work_done)
    end

    {:noreply, %{state | working_nodes: pendingNodes}}
  end

  # ----------------------------------------------------------------------------
  #       Communication between Handlers
  # ----------------------------------------------------------------------------

  # Own Handler inform his schedular about his status 
  @impl true
  def handle_info(
        {:work_update, status, handler},
        %{working_nodes: nodes, handlers: handlers, work_status: workStatus} = state
      ) do
    if handler in handlers do
      Logger.info("Handler #{inspect(handler)} has work update: #{inspect(status)}")
      newStatus = NodeWorkStatus.update_status(status, workStatus)
      inform_peers({:update, status}, nodes)
      {:noreply, %{state | work_status: newStatus}}
    else
      {:noreply, state}
    end
  end

  # Own handler inform his scheduler when job is completed
  def handle_info(
        {:done, id, handler},
        %{nodes: nodes, handlers: handlers} = state
      ) do
    Logger.info("Handler #{inspect(handler)} has done his work #{inspect(id)} ")
    DailyReport.AppWorkSupervisor.stop(handler)
    newhandlers = handlers -- [handler]

    if newhandlers == [] do
      inform_all({:node_completed_jobs, node()}, nodes)
    end

    {:noreply, %{state | handlers: newhandlers}}
  end

  @impl true
  def handle_info(info, state) do
    IO.puts("Unhandled handleinfo: #{inspect(info)} ")
    {:noreply, state}
  end

  defp inform_peers(msg, nodes) do
    inform_all(msg, nodes -- [node()])
  end

  defp inform_all(msg, nodes) do
    for node <- nodes, do: {__MODULE__, node} |> GenServer.cast(msg)
  end
end
