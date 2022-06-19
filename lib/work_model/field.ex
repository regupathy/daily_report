defmodule Field do
  defstruct [:db_column, :file_column, :type, :value]

  
  def new(fileColumn, dbColumn, type) do
    %Field{
      file_column: fileColumn,
      db_column: transform(dbColumn),
      type: type(type)
    }
  end

  def add_value(%Field{}=f,val)do
    %{f| value: val}
  end  

  def db_column(%Field{db_column: nil, file_column: col}), do: String.downcase(col)
  def db_column(%Field{db_column: col}), do: col

  defp type("int"), do: :int
  defp type("float"), do: :float
  defp type("string"), do: :string
  defp type("date"), do: :date
  defp type("datetime"), do: :datetime
  defp type(_), do: :text

  def map_to_field(rows, fields) do

    for {name, value} <- rows do
      # field = List.keyfind!(fields, name, 2)  # reason for search postion 2 is [:db_column,:file_column, :type, :value]
      field = fields |> Enum.find(fn x -> x.file_column == name end )
      %{field | value: value}
    end

  end

  defp transform(str) do
    str
    |> String.to_charlist()
    |> Enum.filter(&(&1 in Enum.concat(?a..?z,?A..?Z) ++ [?\s]))
    |> List.to_string 
    |> String.downcase()
    |> String.trim()
    |> String.replace(" ","_")
  end

end
