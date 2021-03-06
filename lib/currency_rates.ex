defmodule CurrencyRates do
  @moduledoc """
      #{__MODULE__} is maintain the live currency rates limit in ETS table

      only master node fetch the API and slave nodes will get the message from master processes.

  """
  use GenServer
  require Logger

  def share_data(nodes) when is_list(nodes) do
    GenServer.call(__MODULE__, {:share_data, nodes})
  end

  def share_data(node), do: share_data([node])

  def initiate(nodes) do
    GenServer.cast(__MODULE__, {:download_and_broadcast, nodes})
  end

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @currency_table :currency_ets_table

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    api_key = Application.fetch_env!(:daily_report, :openexchangerates_api_key)
    :ets.new(@currency_table, [:set, :protected, :named_table])
    {:ok, %{api_key: api_key}}
  end

  @impl true
  def handle_call({:share_data, nodes}, _from, state) do
    :ets.tab2list(@currency_table) |> broadcast(nodes)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:download_and_broadcast, nodes}, %{api_key: api_key} = state) do
    currency_data = fetch_currency_rate(api_key)
    currency_data |> load()
    currency_data |> broadcast(nodes)
    Logger.info("Downloaded the Currency rates and broadcast to all nodes")
    {:noreply, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:load_data, data}, state) do
    Logger.info("Currency data recevied from master")
    data |> load()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ets.delete(@currency_table)
    :ok
  end

  @doc """
   convert_currency/2 convert the given curreny into USD money value
  """
  def convert_currency([currency], unit), do: convert_currency(currency, unit)

  def convert_currency(currency, unit) do
    case :ets.lookup(@currency_table, unit) do
      [] -> currency
      [{^unit, rate}] -> (String.to_integer(currency) / rate) |> Float.to_string()
    end
  end

  # keeping the local copy of currency rate to avoid calling the live API for dev
  defp fetch_currency_rate(:local) do
    DummyCurrencyRates.data()
  end

  #  private method fetch_currency_rate/1 download the live curreny list from openexchangerates free open API
  ## default appkey for openexchangerates
  # @apikey '23f7639edfb34aecbe04f8c94cea0671'
  defp fetch_currency_rate(api_key) do
    url = 'https://openexchangerates.org/api/latest.json?app_id=#{api_key}'

    case :httpc.request(:get, {url, []}, [{:ssl, [{:verify, :verify_none}]}], []) do
      {:ok, {{'HTTP/1.1', 200, 'OK'}, _headers, body}} ->
        body |> Poison.decode!() |> Map.get("rates")
    end
  end

  defp load(currency_rates),
    do: for({unit, rate} <- currency_rates, do: :ets.insert(@currency_table, {unit, rate}))

  defp broadcast(data, nodes),
    do: for(node <- nodes, do: {__MODULE__, node} |> send({:load_data, data}))
end
