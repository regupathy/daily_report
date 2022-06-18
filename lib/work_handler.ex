defmodule WorkHandler do
  @moduledoc """
    Handler do the following job
    1. copy the given file into working directory of the node ex:) ~/.appname/nodname/date/file.csv
    2. start Agent for file stream  
    3. get the decidated sql worker
    4. get the row from Agent procees(file stream)
    5. calculate the USD price for each row
    6. write N number rows into SQL db
    7. inform his schedular about last processed row number 
    8. repeat the step 4 until the end of file
    9. report the his schedular "i have done my job"
    10.on terminate kill Sql worker
  """
  use GenServer

  defstruct [
    :id,
    :job_name,
    :start_row,
    :destination,
    :sql_worker,
    :work,
    :reporter,
    current_row: 0,
    items_count: 5,
    cache: [],
    cache_count: 0
  ]

  def params(id, job_name, row, destination, items_count \\ 5) do
    %WorkHandler{
      id: id,
      job_name: job_name,
      destination: destination,
      start_row: row,
      items_count: items_count
    }
  end

  def init({%WorkHandler{job_name: job_name} = state, reporter}) do
    work = Work.get(job_name)

    case File.exists?(Work.get_source(work)) do
      true ->
        GenServer.cast(self(), {:start, self()})
        {:ok, %WorkHandler{state | work: work, reporter: reporter}}

      false ->
        {:stop, :file_not_found}
    end
  end

  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  def handle_cast(
        {:start, pid},
        %WorkHandler{work: work, destination: destination, start_row: start_row} = state
      )
      when pid == self() do
    # 1. copy the file into working directory
    # 2. start Agent for file stream  
    source = Work.get_source(work)
    File.copy!(source, destination)
    destination |> Path.join(Path.basename(source)) |> start_stream_agent(work, start_row)
    # 3. get the decidated sql worker
    sql_worker = DailyReport.SqlWorkPoolSupervisor.start()
    {:noreply, %{state | sql_worker: sql_worker}}
  end

  def handle_cast({:row, number, field_values}, %{item_count: n, cache_count: m} = state)
      when m + 1 == n do
    post_job(state.cache ++ [field_values], state)
    # 7. inform his schedular about last processed row number 
    :erlang.send(state.reporter, {:work_update, %{id: state.id, row: state.current_row}, self()})
    {:noreply, %{state | cache: [], current_row: number, cache_count: 0}}
  end

  def handle_cast({:row, number, field_values}, %{cache_count: m, cache: caches} = state) do
    {:noreply,
     %{state | cache: caches ++ [field_values], current_row: number, cache_count: m + 1}}
  end

  def handl_cast(:work_done, %{cache_count: count} = state) do
    if count != 0 do
      post_job(state.cache, state)
      # 7. inform his schedular about last processed row number 
      :erlang.send(
        state.reporter,
        {:work_update, %{id: state.id, row: state.current_row}, self()}
      )
    end

    # 9. report the his schedular "i have done my job"
    :erlang.send(state.reporter, {:done, self()})
    {:noreply, %{state | cache: [], cache_count: 0}}
  end

  def terminate(state) do
    # 10.on terminate kill Sql worker
    DailyReport.SqlWorkPoolSupervisor.stop(state.sql_worker)
  end

  defp start_stream_agent(filepath, work, start_row) do
    reporter = self()
    #  4. get the row from Agent procees(file stream)
    event_fun = fn rows, number ->
      field_values = Field.map_to_field(rows, Work.get_fields(work))
      GenServer.cast(reporter, {:row, number, field_values})
    end

    after_fun = fn -> GenServer.cast(reporter, :work_done) end
    Agent.start_link(fn -> CSVHandler.process(filepath, start_row, event_fun, after_fun) end)
  end

  defp post_job(rows, state) do
    # 6. write N number rows into SQL db
    DbHelper.multinsert(rows, state.sql_worker)
  end
end
