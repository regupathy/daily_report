defmodule DailyDumbTest do
  use ExUnit.Case
  doctest DailyDumb

  test "greets the world" do
    assert DailyDumb.hello() == :world
  end
end
