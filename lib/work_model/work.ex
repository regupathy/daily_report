defmodule Work do
  require Logger

  alias :mnesia, as: Mnesia
  defstruct [:name, :url, :fields, :options]

  def new(name, url, fields, options) do
    %Work{name: name, url: url, fields: fields, options: options}
  end

  def init() do
    case :erlang.nodes() != [] do
      true ->
        Mnesia.start()

      false ->
        Mnesia.stop()
        Mnesia.create_schema(node())
        Mnesia.start()
        Mnesia.change_table_copy_type(:schema, node(), :disc_copies)

        Mnesia.create_table(
          Work,
          [
            {:disc_copies, [node()]},
            # map stored all values in the stored key value orders
            attributes: [:fields, :name, :options, :url],
            index: [:name],
            type: :bag
          ]
        )
    end
  end

  def new_node(node) do
    Mnesia.change_config(:extra_db_nodes, [node])
    Mnesia.change_table_copy_type(:schema, node, :disc_copies)
    Mnesia.add_table_copy(Work, node, :disc_copies)
  end

  def default_fields() do
    [
      # Field.new("revenue","revenue","float") |> Field.add_value(0),
      # Field.new("currency","currency","string") |> Field.add_value("USD"),
      # Field.new("date","date","text") |> Field.add_value("today"),
      Field.new("row_id", "rowid", "int")
    ]
  end

  def conform_required(fields) do
    totalKeys = for %Field{db_column: name} <- fields, do: name

    ["revenue", "currency", "date"]
    |> Enum.all?(fn x -> Enum.member?(totalKeys, x) end)
  end

  def save(%Work{} = work) do
    {:atomic, :ok} =
      fn -> Map.values(work) |> List.to_tuple() |> Mnesia.write() end
      |> Mnesia.transaction()
  end

  def get_all_work_names() do
    Mnesia.dirty_select(Work, [{{Work, :_, :"$1", :_, :_}, [], [:"$1"]}])
  end

  def get_fields(%Work{} = work) do
    work.fields
  end

  def get_source(work) do
    work.url
  end

  def get(workname) do
    [[fields, name, options, url]] =
      Mnesia.dirty_select(Work, [
        {{Work, :"$1", :"$2", :"$3", :"$4"}, [{:==, :"$2", workname}], [:"$$"]}
      ])

    %Work{name: name, fields: fields, options: options, url: url}
  end

  # Mnesia Work table's row order is [:fields, :name,:options, :url]
  def get_all_with_sync() do
    {:atomic, values} =
      fn -> Mnesia.select(Work, [{{Work, :"$1", :"$2", :"$3", :"$4"}, [], [:"$$"]}]) end
      |> Mnesia.transaction()

    for [fields, name, options, url] <- values do
      %Work{name: name, fields: fields, options: options, url: url}
    end
  end

  def get_all() do
    result = Mnesia.dirty_select(Work, [{{Work, :"$1", :"$2", :"$3", :"$4"}, [], [:"$$"]}])

    for [fields, name, options, url] <- result do
      %Work{name: name, fields: fields, options: options, url: url}
    end
  end
end
