defmodule CurrencyRates do
  @moduledoc """
      #{__MODULE__} is maintain the live currency rates limit in ETS table

      only master node fetch the API and slave nodes will get the message from master processes.

  """
  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @currency_table :currency_ets_table

  def init(_opts) do
    api_key = Application.fetch_env!(:daily_dumb, :currency_api_key)
    :ets.new(@currency_table, [:set, :protected, :named_table])
    {:ok, %{api_key: api_key}}
  end

  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  def handle_cast({:download_and_broadcast, nodes}, %{api_key: api_key} = state) do
    currency_data = fetch_currency_rate(api_key)
    currency_data |> load()
    currency_data |> broadcast(nodes)
    {:noreply, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info({:load_data, data}, state) do
    data |> load()
    {:noreply, state}
  end

  @doc """
   convert_currency/2 convert the given curreny into USD money value
  """
  def convert_currency(currency, unit) do
    case :ets.lookup(@currency_table, unit) do
      :undef -> {currency, unit}
      rate -> {currency / rate, "USD"}
    end
  end

  #  private method fetch_currency_rate/1 download the live curreny list from openexchangerates free open API
  ## default appkey for openexchangerates
  # @apikey '23f7639edfb34aecbe04f8c94cea0671'
  defp fetch_currency_rate(api_key) do
    url = 'https://openexchangerates.org/api/latest.json?app_id=#{api_key}'

    case :httpc.request(:get, {url, []}, [], []) do
      {:ok, {{'HTTP/1.1', 200, 'OK'}, _headers, body}} ->
        body |> Poison.decode!() |> Keyword.get("rates")
    end
  end

  defp load(currency_rates),
    do: for({unit, rate} <- currency_rates, do: :ets.insert(@currency_table, {unit, rate}))

  defp broadcast(data, nodes),
    do: for(node <- nodes, do: {node, __MODULE__} |> :erlang.send({:load_data, data}))
end
