defmodule PrometheusExometerTest do
  use ExUnit.Case
  doctest PrometheusExometer

  test "greets the world" do
    assert PrometheusExometer.hello() == :world
  end
end
