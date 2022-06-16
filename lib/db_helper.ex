defmodule DbHelper do
  @database "daily_updates"
  def new() do
    MyXQL.start_link(username: "root", password: "password", database: "#{@database}")
  end

  @table "daily_report"
  def presetup() do
    {:ok, pid} = new()
    MyXQL.query!(pid, "CREATE TABLE  IF NOT exists #{@table} (
                `id` bigint NOT NULL AUTO_INCREMENT,
                `row_id` int NOT NULL,
                `task` varchar(50) NOT NULL,
                `revenue` Double NOT NULL,
                `currency` varchar(5) NOT NULL,
                `date` date NOT NULL,
                `on_create` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `last_updated` TIMESTAMP ON UPDATE CURRENT_TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                primary key (id)
              );
              ")
    GenServer.stop(pid)
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
    columns = for %Field{db_column: col, type: t} <- fields, do: "#{col}  #{db_type(t)}"
    {:ok, _} = MyXQL.query!(conn, "ALTER Table #{@table} ADD " <> Enum.join(columns, " , "))
  end

  defp db_type(%Field{type: :int}), do: "int(32) Null"
  defp db_type(%Field{type: :float}), do: "Float(32) Null"
  defp db_type(%Field{type: :string}), do: "varchar(255) Null"
  defp db_type(%Field{type: :date}), do: "date Null"
  defp db_type(%Field{type: :datetime}), do: "datetime Null"
  defp db_type(_), do: "text"

  @doc """
  method insert/2 used to insert the values into table #{@table}
  """
  def insert(fields_values, conn) when is_list(fields_values) do
    cols = for x <- fields_values, do: "'#{x.db_column}'"
    place_holder = String.duplicate("?", length(fields_values)) |> Enum.join(",")
    params = for fval <- fields_values, do: db_val(fval)
    statement = "INSERT INTO #{@table}(" <> Enum.join(cols, " , ") <> ")VALUES(#{place_holder})"
    MyXQL.query(conn, statement, params)
  end

  defp db_val({%Field{type: :int}, val}) when is_integer(val), do: Integer.to_string(val)
  defp db_val({%Field{type: :float}, val}) when is_float(val), do: Float.to_string(val)
  defp db_val(_, val) when is_binary(val), do: val

  # escape_binary(Bin) when is_binary(Bin) ->
  #     [<<"X'">>, base16:encode(Bin), <<"'">>].
end
