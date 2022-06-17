defmodule AppNodeManager do
  @moduledoc false

  use GenServer

  # Callbacks
  @impl true 
  def init(_opts) do
    :global.sync()
    :net_kernel.monitor_nodes(true, [:nodedown_reason])
    res = :global.register_name(__MODULE__, self(), &:global.random_notify_name/3)
    :timer.send_after(1000, self(), :process_next)
    status = if res == :yes, do: true, else: false
    {:ok, %{master: status}}
  end

  @impl true
  def handle_call(_msg,_from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:global_name_conflict, __MODULE__}, state) do
    {:ok, %{state | master: false}}
  end

  def handle_info(:process_next, %{master: true} = state) do
    RestAPISupervisor.enable_rest_api()
    {:ok, state}
  end

  def handle_info({:nodeup, _node}, %{master: true} = state) do
    {:ok, state}
  end

  def handle_info({:nodedown, _node, [{:nodedown_reason, _reason}]}, %{master: true} = state) do
    :global.sync()
    ## :TODO reassign the job of the node
    {:ok, state}
  end

  def handle_info({:nodeup, _node, []}, %{master: true} = state) do
    {:ok, state}
  end

  def handle_info({:nodeup, _node, []}, state) do
    {:ok, state}
  end

  def handle_info({:nodedown, _node, [{:nodedown_reason, _reason}]}, state) do
    {:ok, state}
  end

  def handle_info(_msg, state), do: {:ok, state}
end
