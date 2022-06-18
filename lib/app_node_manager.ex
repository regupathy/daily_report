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

  def to_global(msg) do
    :global.send(AppNodeManager, {msg, self})
  end

  def start_work()do
    :global.send(AppNodeManager,:start_work)
  end

  # Callbacks
  @impl true
  def init(_opts) do
    # waiting for the others to start sync
    :global.sync()
    # requesting the kernal for monitor_node subscription
    :net_kernel.monitor_nodes(true, [:nodedown_reason])
    res = :global.register_name(AppNodeManager, self(), &:global.random_notify_name/3)
    if res == :yes do
      :timer.send_after(1000, self(), :process_next)   
    {:ok, %{master: true, master_node: nil, active_nodes: [node()|nodes()] ,work_start?: false }}
      else 
    {:ok, %{master: false,,work_start?: false,active_nodes: [node()|nodes()],
     master_node: :global.whereis_name(AppNodeManager) |> node() }}
      end
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:work_started,state)do
    {:noreply,%{state | work_start?: true}}
  end

  @impl true
  # Conflict happens when try to register globally 
  # other node got the opportunity so we got this signal
  # this node not a master node continous as slave node 
  def handle_info({:global_name_conflict, __MODULE__}, state) do
    {:noreply, %{state | master: false}}
  end

  def handle_info(:process_next, %{master: true} = state) do
    DailyReport.RestAPISupervisor.enable_rest_api()
    CurrencyRates.initiate(nodes())
    WorkScheduler.markAsMaster()
    # After become a master node 
    if state.
    {:noreply, %{state| master_node: node()}}
  end

# ---------------------------------------------------------------------------------
#                 Handling Node Up Signal
# ---------------------------------------------------------------------------------
  # Master Node receive the slave node Node UP Signal
  def handle_info({:nodeup, node, _}, %{master: true} = state) do
    Logger.info(" Master Node:  Node #{node} joined in the Cluster ")
    :global.sync()
    {:noreply, state}
  end

  # Slave Node receive other Slave node Node UP signal
  def handle_info({:nodeup, node, _}, %{active_nodes: active_nodes} =state) do
    Logger.info("Slave Node:  Node #{node} joined in the Cluster ")
    {:noreply,%{state | active_nodes: [node| active_nodes] }}
  end

# ---------------------------------------------------------------------------------
#                 Handling Node Down Signal
# ---------------------------------------------------------------------------------
    # Master Node receive  slave node DOWN signal
    def handle_info({:nodedown, node, _}, %{master: true, active_nodes: active_nodes} = state) do
      newCluster = active_nodes -- [node]
      # Master node check with Work scheduler to rebalancing the work of Downed node 
      if state.work_start? do
        WorkScheduler.rebalance_work(newCluster)
      end
      {:noreply,%{state| active_nodes: newCluster}}
    end

  # Slave Node receive the Master node DOWN Signal
  def handle_info({:nodedown, node, _}, %{master_node: ^node,active_nodes: active_nodes} =state) do
    res = :global.register_name(AppNodeManager, self(), &:global.random_notify_name/3)
    if res == :yes do
      :timer.send_after(1000, self(), :process_next)   
    {:noreply, %{state | master: true, master_node: nil, active_nodes: [node| active_nodes]  }}
      else 
    {:noreply, %{state | master: false,, active_nodes: [node| active_nodes],
     master_node: :global.whereis_name(AppNodeManager) |> node() }}
      end
  end

  # Slave Node receive other slave node DOWN signal
  def handle_info({:nodedown, node, _}, %{active_nodes: active_nodes} =state) do
      {:noreply,%{state| ,active_nodes: active_nodes -- [node]}}
  end

  # def handle_info({:nodedown, _node, [{:nodedown_reason, _reason}]}, state) do
  #   {:ok, state}
  # end
  
# ---------------------------------------------------------------------------------
#                 Initiate the work
# ---------------------------------------------------------------------------------
  def handle_info(:start_work, state) do 
    WorkScheduler.start_work(nodes() ++ [node()])
    inform_peers(:work_started)
    {:noreply, %{state | :work_start?: true}}
  end

# ---------------------------------------------------------------------------------
#                 Helper Functions
# ---------------------------------------------------------------------------------
defp inform_peers(msg, nodes)do
  exceptMe = nodes -- [node()]
   for(node <- exceptMe, do: {node, __MODULE__} |> GenServer.cast(msg))

end

end
