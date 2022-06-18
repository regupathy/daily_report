defmodule CSVHandler do
  def get_stream(filepath, header?) do
    filepath
    |> Path.expand(__DIR__)
    |> File.stream!()
    |> CSV.decode(headers: header?)
  end

  def header(stream) do
    for x <- stream |> Enum.take(1) do
      x |> String.trim() |> String.downcase()
    end
  end

  def process(filepath, start_row, eventfunc, endfunc) do
    get_stream(filepath, true)
    |> Stream.with_index()
    |> Stream.map(fn {row, num} ->
      if start_row < num do
        eventfunc.(num, row)
      end
    end)
    |> Stream.run()

    endfunc.()
  end
end
