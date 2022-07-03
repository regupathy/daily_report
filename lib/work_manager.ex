defmodule WorkManager do
  defstruct [:work_state, :workname, :destination, handlers: %{}, master: false, pending_jobs: []]

  use GenServer
  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
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

  def rebalance_work(_name, _nodes) do
    # GenServer.call(WorkScheduler, {:rebalance_work, name, nodes})
  end

  # ------------------------------------------------------------------------------
  #                 GenServer CallBacks
  # ------------------------------------------------------------------------------

  @impl true
  def init([]) do
    Process.flag(:trap_exit, true)
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

  def handl_call(:hand_over, from, %{workname: name, pending_jobs: [job | jobs]} = state) do
    WorkState.update_status(name, {:hand_over, job, node(), node(from)})
    {:reply, [job], %{state | pending_jobs: jobs}}
  end

  @impl true
  def handle_cast({:work_begin, %{workname: workname}}, state) do
    destination = Path.join("output", workname)
    File.mkdir(destination)
    {:ok, work_state} = WorkState.start_link(workname, state.work_status)
    pendingJobs = WorkState.get_my_job(workname)
    Process.send_after(self(), {:check_job, 2}, 1)

    {:noreply,
     %{state | work_state: work_state, pending_jobs: pendingJobs, destination: destination}}
  end

  def handle_cast({:hand_over_jobs, handOver}, %{pending_jobs: pending_jobs} = state) do
    {:noreply, %{state | pending_jobs: pending_jobs ++ handOver}}
  end

  @impl true
  def handle_info({:check_job, n}, %{pending_jobs: []} = state) do
    busyNodes = WorkState.get_busy_nodes(state.workname)
    request_jobs(busyNodes, n)
    {:noreply, state}
  end

  def handle_info({:check_job, n}, %{handlers: handlers, pending_jobs: [job | jobs]} = state) do
    handler = create_handler(job, state.destination)
    if n - 1 > 0, do: Process.send_after(self(), {:check_job, n - 1}, 1)
    {:noreply, %{state | handlers: Map.put(handlers, handler, elem(1, job)), pending_jobs: jobs}}
  end

  defp create_handler({id, job_name, row}, destination) do
    {:ok, ref} =
      WorkHandler.params(id, job_name, row, destination)
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

    Process.spawn(
      fn ->
        handOver = loop(busyNodes, 0, n, [])
        if handOver != [], do: GenServer.cast(self, {:hand_over_jobs, handOver})
        pendingWorkers = if length(handOver) < n, do: length(handOver), else: n
        Enum.each(pendingWorkers, fn _ -> send({:check_job, 1}, self) end)
      end,
      [:monitor]
    )
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
