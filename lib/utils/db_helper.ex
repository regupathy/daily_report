defmodule DbHelper do
  # @database "daily_updates"

  require Logger

  def new() do
    DailyReport.SqlWorkPoolSupervisor.start()
  end

  def close(ref) do
    DailyReport.SqlWorkPoolSupervisor.stop(ref)
  end

  @table "daily_report"
  def presetup() do
    {:ok, pid} = new()
    MyXQL.query!(pid, "CREATE TABLE  IF NOT exists #{@table} (
                `id` bigint NOT NULL AUTO_INCREMENT,
                `rowid` int NOT NULL,
                `revenue` TEXT NOT NULL,
                `currency` varchar(50) NOT NULL,
                `date` TEXT NOT NULL,
                `on_create` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `last_updated` TIMESTAMP ON UPDATE CURRENT_TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                primary key (id)
              );
              ")
    close(pid)
  end

  def get_all_columns(conn) do
    res = MyXQL.query(conn, "SELECT column_name
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = N'#{@table}'")

    case res do
      {:ok, %MyXQL.Result{rows: rows}} -> for [x] <- rows, do: x
      _ -> []
    end
  end

  @doc """
  method update_coulmns/2 will add extra columns to the #{@table}
  """
  def update_coulmns([], _), do: :ok

  def update_coulmns(fields, conn) when is_list(fields) do
    columns = for %Field{db_column: col, type: t} <- fields, do: "ADD COLUMN #{col}  #{db_type(t)}"
    query = "ALTER Table #{@table} " <> Enum.join(columns, " , ")
    Logger.info(query)
    %MyXQL.Result{} = MyXQL.query!(conn, query)
  end

  defp db_type(%Field{type: :int}), do: "int(32) Null"
  defp db_type(%Field{type: :float}), do: "Float(32) Null"
  defp db_type(%Field{type: :string}), do: "varchar(255) Null"
  defp db_type(%Field{type: :date}), do: "date Null"
  defp db_type(%Field{type: :datetime}), do: "datetime Null"
  defp db_type(_), do: "TEXT NULL"

  @doc """
  method insert/2 used to insert the values into table #{@table}
  """
  def insert(fields_values, conn) when is_list(fields_values) do
    cols = for {x, _} <- fields_values, do: "'#{x.db_column}'"
    place_holder = List.duplicate("?", length(fields_values)) |> Enum.join(",")
    params = for {_, fval} <- fields_values, do: db_val(fval)
    statement = "INSERT INTO #{@table}(" <> Enum.join(cols, " , ") <> ")VALUES(#{place_holder})"
    MyXQL.query(conn, statement, params)
  end

  def multinsert([],_),do: :done
  def multinsert(fields_values, conn) when is_list(fields_values) do
    cols = for x <- hd(fields_values), do: "`#{x.db_column}`"
    single_holder = List.duplicate("?", length(cols)) |> Enum.join(",")

    place_holder =
      List.duplicate("(" <> single_holder <>")",length(fields_values)) |> Enum.join(",")

    params =
      for items <- fields_values do
        for x <- items, do: db_val(x)
      end

    statement = "INSERT INTO #{@table}(" <> Enum.join(cols, " , ") <> ")VALUES#{place_holder}"
    {:ok,%MyXQL.Result{}}  = MyXQL.query(conn, statement, Enum.concat(params))
  end

  defp db_val(%Field{type: :int, value: val}) when is_integer(val), do: Integer.to_string(val)
  defp db_val(%Field{type: :float, value: val}) when is_float(val), do: Float.to_string(val)
  defp db_val(%Field{value: val}) when is_binary(val), do: val
  # defp db_val(%Field{value: val}) when is_binary(val), do: "X'#{:base64.encode(val)}'"
end
