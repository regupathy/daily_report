defmodule CSVHandler do
  def get_stream(filepath, header?) do
    filepath
    |> File.stream!()
    |> CSV.decode(headers: header?)
  end

  def header(stream) do
    [ok: header]  = stream |> Enum.take(1)
    header
  end

  def process(filepath, start_row, eventfunc, endfunc) do
    get_stream(filepath, true)
    |> Stream.with_index()
    |> Stream.map(fn {{:ok,row}, num} ->
      if start_row < num do
        eventfunc.(num, row)
      end
    end)
    |> Stream.run()

    endfunc.()
  end
end
