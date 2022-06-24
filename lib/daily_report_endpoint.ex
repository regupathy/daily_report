defmodule DailyReportEndpoint do
  use Plug.Router
  # This module is a Plug, that also implements it's own plug pipeline, below:
  # Using Plug.Logger for logging request information
  plug(Plug.Logger)
  # responsible for matching routes
  plug(:match)
  # Using Poison for JSON decoding
  # Note, order of plugs is important, by placing this _after_ the 'match' plug,
  # we will only parse the request AFTER there is a route match.
  plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
  # responsible for dispatching responses
  plug(:dispatch)

  require Logger
  # Handle incoming events, if the payload is the right shape, process the
  # events, otherwise return an error.
  post "/job" do
    {status, body} =
      case conn.body_params do
        %{"name" => _, "source" => _, "mapping" => _} = job ->
          {200, process_job(job)}

        _ ->
          {422,
           Poison.encode!(%{
             error: "Expected Payload: { 'name': ?, 'source': ? , 'auto': true | false,
        'mapping' : [ {'column': ? , 'to': ? , 'type': 'int' | 'text' | 'string' } ] }"
           })}
      end

    send_resp(conn, status, body)
  end

  defp process_job(job) do
    try do
      with headers <- CSVHandler.get_stream(job["source"], false) |> CSVHandler.header(),
           usersFields <- map_to_field(job["mapping"]),
           fields <- header_to_fields(headers, usersFields),
           true <- Work.conform_required(fields) do
        fields = Enum.concat(fields,Work.default_fields()) 
        Work.new(job["name"], job["source"], fields, []) |> Work.save()
        update_db_table(fields)
        Poison.encode!(%{response: "Accepted the job #{job["name"]}"})
      else
        any -> handle_error(any, job)
      end
    rescue
      any -> handle_error(any, job)
    end
  end

  defp handle_error(%File.Error{reason: :enoent}, job) do
    Poison.encode!(%{response: "source #{job["source"]} is not found"})
  end
  defp handle_error(false, job) do
    Poison.encode!(%{response: "source #{job["source"]} is not contains required columns revenue currency date"})
  end
  defp handle_error(any, job) do
    Logger.info(" any : #{inspect(any)}")
    Poison.encode!(%{response: "job #{job["name"]} is not accepted"})
  end

  defp map_to_field(mappings) do
    for %{"column" => column} = map <- mappings, into: %{} do
      to = map["to"] || column
      type = map["type"] || "string"
      {column, Field.new(column, to, type(type))}
    end
  end

  defp header_to_fields(headers, fieldmap) do
    for name <- headers, do: fieldmap[name] || Field.new(name, Field.transform(name), :string)
  end

  defp update_db_table(fields)do
    {:ok,pid} = DailyReport.SqlWorkPoolSupervisor.start()
    columns = DbHelper.get_all_columns(pid)
    fields = fields |> Enum.filter(fn x -> x.db_column not in columns end)
    Logger.info(" New fields : #{inspect(fields)}")
    DbHelper.update_coulmns(fields,pid)
    DailyReport.SqlWorkPoolSupervisor.stop(pid)
  end

  defp type("int"), do: :int
  defp type("string"), do: :string
  defp type("float"), do: :float
  defp type("date"), do: :date
  defp type("datetime"), do: :datetime
  defp type(_), do: :text

  # A catchall route, 'match' will match no matter the request method,
  # so a response is always returned, even if there is no route to match.
  match _ do
    send_resp(conn, 404, "oops... Nothing here :(")
  end
end
