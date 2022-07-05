defmodule WorkManager do
  defstruct [:work_state, :workname, :destination, is_active: false, handlers: %{}, master: false, pending_jobs: []]

  use GenServer
  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  # ------------------------------------------------------------------------------
  #                 API only for AppNodeManager
  # ------------------------------------------------------------------------------

  def markAsMaster() do
    GenServer.call(WorkManager, :be_master)
  end

  def start_work(name, nodes) do
    GenServer.call(WorkManager, {:begin_work, nodes, name})
  end

  def rebalance_work(_name, _nodes) do
    # GenServer.call(WorkScheduler, {:rebalance_work, name, nodes})
  end

  def all_done()do
    GenServer.cast(WorkManager,:all_done)
  end

  # ------------------------------------------------------------------------------
  #                 GenServer CallBacks
  # ------------------------------------------------------------------------------

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)
    Work.init()
    {:ok, %WorkManager{}}
  end

  @impl true
  def handle_call(:be_master, _from, state) do
    {:reply, :ok, %{state | master: true}}
  end

  def handle_call({:begin_work, nodes, name}, _from, %{master: true} = state) do
    works = nodes |> Stream.cycle() |> Enum.zip(Work.get_all_work_names())
    schedule = for {node, work_name} <- works, do: {make_ref(), node, work_name}
    workStatus = NodeWorkStatus.new(schedule)
    Logger.info("Work Schedule is : #{inspect(workStatus)}")
    inform_all({:work_begin, %{work_status: workStatus, nodes: nodes, workname: name}}, nodes)
    {:reply, :ok, state}
  end

  def handle_call(:hand_over, _from, %{pending_jobs: []} = state) do
    {:reply, [], state}
  end

  def handle_call(:hand_over, {from,_}, %{workname: name, pending_jobs: pending_jobs} = state) do
    [{jobId,_,_}=job | jobs] = pending_jobs
    WorkState.reassign(name, jobId, node(), node(from))
    Logger.info(" share my job #{inspect(jobId)} to #{inspect(node(from))}")
    {:reply, [job], %{state | pending_jobs: jobs}}
  end

  @impl true
  def handle_cast({:work_begin, %{work_status: workStatus,workname: workname}}, state) do
    destination = Path.join("output", workname)
    File.mkdir(destination)
    {:ok, work_state} = WorkState.start_link(workname, workStatus)
    WorkState.print(workname)
    pendingJobs = WorkState.get_my_job(workname)
    Process.send_after(self(), {:check_job, 2}, 1)

    {:noreply,
     %{state |workname: workname, is_active: true, work_state: work_state, pending_jobs: pendingJobs, destination: destination}}
  end

  def handle_cast({:hand_over_jobs, handOver}, %{pending_jobs: pending_jobs} = state) do
    Logger.info(" Recieved handover jobs : #{inspect(handOver)}")
    {:noreply, %{state | pending_jobs: pending_jobs ++ handOver}}
  end

  def handle_cast(:all_done,state)do
    WorkState.print(state.workname)
    Process.spawn(fn ->
      Process.sleep(2000) 
      GenServer.stop(state.work_state)
    end,[])
    if state.master do
      AppNodeManager.to_global(:work_done)
    end
    {:noreply,state}
  end

  @impl true
  def handle_info({:check_job, _n}, %{is_active: false } = state), do: {:noreply,state} 
  def handle_info({:check_job, n}, %{pending_jobs: []} = state) do
    busyNodes = WorkState.get_busy_nodes(state.workname)
    request_jobs(busyNodes, n)
    {:noreply, state}
  end

  def handle_info({:check_job, n}, %{handlers: handlers, pending_jobs: [job | jobs]} = state) do
    handler = create_handler(state.workname,job, state.destination)
    if n - 1 > 0, do: Process.send_after(self(), {:check_job, n - 1}, 1)
    {:noreply, %{state | handlers: Map.put(handlers, handler, elem(job,1)), pending_jobs: jobs}}
  end

  def handle_info({:done, jobId, handler},state)do
    Logger.info(" handler #{inspect(handler)} completed the job : #{inspect(jobId)} ")
    Process.send_after(self(), {:check_job, 1}, 1)
    {:noreply,%{state | handlers: Map.delete(state.handlers,handler)} }
  end

  def handle_info(_,state)do
    {:noreply,state}
  end

  defp create_handler(job_title,{id, job_name, row}, destination) do
    {:ok, ref} =
      WorkHandler.params(id, job_name, job_title, row, destination)
      |> DailyReport.AppWorkSupervisor.start_work()

    Logger.info("Handlers created for #{job_name} are #{inspect(ref)}")
    ref
  end

#   defp inform_peers(msg, nodes) do
#     inform_all(msg, nodes -- [node()])
#   end

  defp inform_all(msg, nodes) do
    for node <- nodes, do: {__MODULE__, node} |> GenServer.cast(msg)
  end

  defp request_jobs([], _n), do: :ignore

  defp request_jobs(busyNodes, n) do
    self = self()
    fun = fn ->
      handOver = loop(busyNodes, 0, n, [])
      if handOver != [] do 
        GenServer.cast(self, {:hand_over_jobs, handOver})
        Enum.each(1..length(handOver), fn _ -> send(self,{:check_job, 1}) end)
      end
    end
    Process.spawn(fun,[])
  end

  defp loop(_, n, n, jobs), do: jobs
  defp loop(_, _c, n, jobs) when length(jobs) == n, do: jobs

  defp loop(nodes, c, n, jobs) do
    node = Stream.cycle(nodes) |> Enum.at(c)

    case GenServer.call({WorkManager, node}, :hand_over) do
      [] -> loop(nodes, c + 1, n, jobs)
      [job] -> loop(nodes, c + 1, n, [job | jobs])
    end
  end
end
