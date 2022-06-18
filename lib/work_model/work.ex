defmodule Work do
  alias :mnesia, as: Mnesia
  defstruct [:name, :url, :fields, :options]

  def new(name, url, fields, options) do
    %Work{name: name, url: url, fields: fields, options: options}
  end

  def init() do
    Mnesia.stop()
    Mnesia.create_schema(node())
    Mnesia.start()
    Mnesia.change_table_copy_type(:schema,node(),:disc_copies)
  end

  def new_node(node)do
    Mnesia.change_config(:extra_db_nodes, [node])
    Mnesia.add_table_copy(Work,node,:disc_copies)
  end

  def conform_required(fields) do
    totalKeys = for %Field{db_column: name} <- fields, do: name

    ["revenue", "currency", "date"]
    |> Enum.all?(fn x -> Enum.member?(totalKeys, x) end)
  end

  def save(%Work{} = work) do
    fn -> Mnesia.write(Map.values(work)) end
    |> Mnesia.transaction()
  end

  def get(workname) do
    Mnesia.dirty_read(Work, workname)
  end

  def get_all_work_names() do
    Mnesia.dirty_read(Work, [{{'$1', '_', '_'}, [], '$1'}])
  end

  def get_fields(%Work{} = work) do
    work.fields
  end

  def get_source(work) do
    work.url
  end

  def get_all() do
    Mnesia.dirty_read(Work)
  end
end


