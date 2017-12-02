defmodule PrometheusExometerTest do
  use ExUnit.Case
  # doctest PrometheusExometer

  # test "greets the world" do
  #   assert PrometheusExometer.hello() == :world
  # end

  test "convert_unit" do
    assert PrometheusExometer.convert_unit(:us, :seconds, 1) == 0.000001
    assert PrometheusExometer.convert_unit(:foo, :bar, 1) == 1

    assert PrometheusExometer.convert_unit(%{unit: :us, export_unit: :seconds}, 1) == 0.000001
    assert PrometheusExometer.convert_unit(%{}, 1) == 1
  end

  test "suffix" do
    assert PrometheusExometer.suffix(%{suffix: :us}) == [:us]
    assert PrometheusExometer.suffix(%{suffix: [:foo, :us]}) == [:foo, :us]
    assert PrometheusExometer.suffix(%{}) == []
  end

  test "strip_prefix" do
    assert PrometheusExometer.strip_prefix([], [:foo, :bar]) == [:foo, :bar]
    assert PrometheusExometer.strip_prefix([:foo], [:foo, :bar]) == [:bar]
    assert PrometheusExometer.strip_prefix([:foo, :bar], [:foo, :bar, :baz]) == [:baz]
  end

  test "split_name_labels" do
    assert PrometheusExometer.split_name_labels([:foo, :bar], %{parent: [:foo]}) == {[:foo], [:bar]}
    assert PrometheusExometer.split_name_labels([:foo, :bar], %{}) == {[:foo, :bar], []}
  end

end
