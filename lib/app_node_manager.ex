defmodule AppNodeManager do
  @moduledoc """

      AppNodeManager is main controller for the cluster of nodes

      Each node has one local AppNodeManager processes
      
      One of the local process tires to become a global processes

      this processes  subscribed to the capturing cluster node changes events

      using this event, it can matain the master/slave nodes 

      Global AppNodeManger Node will perform 

          Rest API
          Controll the Work schedueling 

  """
  use GenServer

  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def to_global(msg) do
    :global.send(AppNodeManager, {msg, self()})
  end

  def start_work(name) do
    :global.send(AppNodeManager, {:start_work, name})
  end

  # Callbacks
  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    # waiting for the others to start sync
    :global.sync()
    # requesting the kernal for monitor_node subscription
    :net_kernel.monitor_nodes(true, [:nodedown_reason])
    res = :global.register_name(AppNodeManager, self(), &:global.random_notify_name/3)
    clusterNodes = :erlang.nodes()
    IO.puts(" APP Node Manager started")

    if res == :yes do
      # :timer.send_after(1000, self(), :process_next)
      Process.send_after(self(), :process_next, 1000)

      {:ok,
       %{
         master: true,
         master_node: nil,
         active_nodes: [node() | clusterNodes],
         work_start?: false,
         work_name: nil
       }}
    else
      {:ok,
       %{
         master: false,
         work_start?: false,
         active_nodes: [node() | clusterNodes],
         master_node: :global.whereis_name(AppNodeManager) |> node(),
         work_name: nil
       }}
    end
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:work_started, name}, state) do
    {:noreply, %{state | work_start?: true, work_name: name}}
  end

  @impl true
  # Conflict happens when try to register globally 
  # other node got the opportunity so we got this signal
  # this node not a master node continous as slave node 
  def handle_info({:global_name_conflict, __MODULE__}, state) do
    {:noreply, %{state | master: false}}
  end

  def handle_info(:process_next, %{master: true, active_nodes: active_nodes} = state) do
    Logger.info("Node #{node()} becomes a master ")
    DailyReport.RestAPISupervisor.enable_rest_api()
    CurrencyRates.initiate(state.active_nodes)
    DbHelper.presetup()
    WorkManager.markAsMaster()

    if state.work_start? do
      WorkManager.rebalance_work(state.work_name, active_nodes)
    end

    {:noreply, %{state | master: true, master_node: node()}}
  end

  def handle_info({:work_done, _}, state) do
    Logger.info("Work #{inspect(state.work_name)} has been completed  !!!! ")
    {:noreply, %{state | work_start?: false, work_name: nil}}
  end

  # ---------------------------------------------------------------------------------
  #                 Handling Node Up Signal
  # ---------------------------------------------------------------------------------
  # Master Node receive the slave node Node UP Signal
  def handle_info({:nodeup, node, _}, %{master: true, active_nodes: active_nodes} = state) do
    Logger.info(" Master Node:  Node #{node} joined in the Cluster ")
    Work.new_node(node)
    CurrencyRates.share_data(node)
    :global.sync()
    Logger.info("current active nodes : #{inspect([node | active_nodes])}")
    {:noreply, %{state | active_nodes: [node | active_nodes]}}
  end

  # Slave Node receive other Slave node Node UP signal
  def handle_info({:nodeup, node, _}, %{active_nodes: active_nodes} = state) do
    Logger.info("Slave Node:  Node #{node} joined in the Cluster ")
    {:noreply, %{state | active_nodes: [node | active_nodes]}}
  end

  # ---------------------------------------------------------------------------------
  #                 Handling Node Down Signal
  # ---------------------------------------------------------------------------------
  # Master Node receive  slave node DOWN signal
  def handle_info({:nodedown, node, _}, %{master: true, active_nodes: active_nodes} = state) do
    newCluster = active_nodes -- [node]
    # Master node check with Work scheduler to rebalancing the work of Downed node 
    if state.work_start? do
      WorkManager.rebalance_work(state.work_name, newCluster)
    end

    {:noreply, %{state | active_nodes: newCluster}}
  end

  # Slave Node receive the Master node DOWN Signal
  def handle_info(
        {:nodedown, node, _},
        %{master_node: master_node, active_nodes: active_nodes} = state
      )
      when node == master_node do
    res = :global.register_name(AppNodeManager, self(), &:global.random_notify_name/3)

    if res == :yes do
      Process.send_after(self(), :process_next, 1000)
      {:noreply, %{state | master: true, master_node: nil, active_nodes: active_nodes -- [node]}}
    else
      {:noreply,
       %{
         state
         | master: false,
           active_nodes: active_nodes -- [node],
           master_node: :global.whereis_name(AppNodeManager) |> node()
       }}
    end
  end

  # Slave Node receive other slave node DOWN signal
  def handle_info({:nodedown, node, _}, %{active_nodes: active_nodes} = state) do
    {:noreply, %{state | active_nodes: active_nodes -- [node]}}
  end

  # def handle_info({:nodedown, _node, [{:nodedown_reason, _reason}]}, state) do
  #   {:ok, state}
  # end

  # ---------------------------------------------------------------------------------
  #                 Initiate the work
  # ---------------------------------------------------------------------------------
  def handle_info({:start_work, name}, state) do
    WorkManager.start_work(name, state.active_nodes)
    inform_peers({:work_started, name}, state.active_nodes)
    {:noreply, %{state | work_start?: true, work_name: name}}
  end

  # ---------------------------------------------------------------------------------
  #                 Helper Functions
  # ---------------------------------------------------------------------------------
  defp inform_peers(msg, nodes) do
    exceptMe = nodes -- [node()]
    for node <- exceptMe, do: {__MODULE__, node} |> GenServer.cast(msg)
  end
end
