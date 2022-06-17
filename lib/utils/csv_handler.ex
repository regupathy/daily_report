defmodule CSVHandler do
  def get_stream(filepath) do
    filepath
    |> Path.expand(__DIR__)
    |> File.stream!()
    |> CSV.decode()
  end

  def header(stream) do
    for x <- stream |> Enum.take(1) do
      x |> String.trim() |> String.downcase()
    end
  end

  def next(stream) do
    stream |> Enum.take(1)
  end
end
