defmodule EndpointTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @opts DailyDumbEndpoint.init([])

  test "it returns 200 with a valid payload" do
    # Create a test connection
    conn = conn(:post, "/job", %{events: [%{}]})

    # Invoke the plug
    conn = DailyDumbEndpoint.call(conn, @opts)

    # Assert the response
    assert conn.status == 200
  end

  test "it returns 422 with an invalid payload" do
    # Create a test connection
    conn = conn(:post, "/job", %{})

    # Invoke the plug
    conn = DailyDumbEndpoint.call(conn, @opts)

    # Assert the response
    assert conn.status == 422
  end
end
