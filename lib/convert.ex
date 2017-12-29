defmodule PrometheusExometer.Convert do
  @moduledoc false

  # These functions convert values for output
  #
  # They are internal, exported only so that they can be accessed by tests

  @spec convert_unit(map, term) :: term
  def convert_unit(prometheus_options, value)
  def convert_unit(%{unit: from, export_unit: to}, value), do: convert_unit(from, to, value)
  def convert_unit(_, value), do: value

  @spec convert_unit(atom, atom, term) :: term
  def convert_unit(from, to, value)
  def convert_unit(:us, :seconds, value), do: value / 1_000_000
  def convert_unit(_, _, value), do: value

  @spec suffix(map) :: list
  def suffix(prometheus_options)
  def suffix(%{suffix: suffix}) when is_list(suffix), do: suffix
  def suffix(%{suffix: suffix}), do: [suffix]
  def suffix(_), do: []

  # Separate name and labels from Exometer name.
  @spec split_name_labels(:exometer.name, map) :: {:exometer.name, list}
  def split_name_labels(exometer_name, prometheus_options)
  def split_name_labels(exometer_name, %{parent: parent}), do: {parent, strip_prefix(parent, exometer_name)}
  def split_name_labels(exometer_name, _options), do: {exometer_name, []}

  @spec strip_prefix(list, list) :: list
  def strip_prefix([head | rest1], [head | rest2]), do: strip_prefix(rest1, rest2)
  def strip_prefix([], labels), do: labels

end
