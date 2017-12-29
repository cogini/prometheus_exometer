defmodule ConvertTest do
  use ExUnit.Case
  # doctest PrometheusExometer

  # test "greets the world" do
  #   assert PrometheusExometer.hello() == :world
  # end

  import PrometheusExometer.Convert

  test "convert_unit" do
    assert convert_unit(:us, :seconds, 1) == 0.000001
    assert convert_unit(:foo, :bar, 1) == 1

    assert convert_unit(%{unit: :us, export_unit: :seconds}, 1) == 0.000001
    assert convert_unit(%{}, 1) == 1
  end

  test "suffix" do
    assert suffix(%{suffix: :us}) == [:us]
    assert suffix(%{suffix: [:foo, :us]}) == [:foo, :us]
    assert suffix(%{}) == []
  end

  test "strip_prefix" do
    assert strip_prefix([], [:foo, :bar]) == [:foo, :bar]
    assert strip_prefix([:foo], [:foo, :bar]) == [:bar]
    assert strip_prefix([:foo, :bar], [:foo, :bar, :baz]) == [:baz]
  end

  test "split_name_labels" do
    assert split_name_labels([:foo, :bar], %{parent: [:foo]}) == {[:foo], [:bar]}
    assert split_name_labels([:foo, :bar], %{}) == {[:foo, :bar], []}
  end

end
