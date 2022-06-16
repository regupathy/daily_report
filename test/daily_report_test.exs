defmodule DailyReportTest do
  use ExUnit.Case
  doctest DailyReport

  test "greets the world" do
    assert DailyReport.hello() == :world
  end
end
