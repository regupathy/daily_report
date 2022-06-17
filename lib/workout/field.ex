defmodule Field do
  defstruct [:file_column, :db_column, :type]

  def new(fileColumn, dbColumn, type) do
    %Field{
      file_column: fileColumn,
      db_column: String.downcase(dbColumn),
      type: type(type)
    }
  end

  def db_column(%Field{db_column: nil, file_column: col}), do: String.downcase(col)
  def db_column(%Field{db_column: col}), do: col

  defp type("int"), do: :int
  defp type("float"), do: :float
  defp type("string"), do: :string
  defp type("date"), do: :date
  defp type("datetime"), do: :datetime
  defp type(_), do: :text

  
end
