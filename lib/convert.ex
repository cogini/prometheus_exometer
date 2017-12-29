defmodule PrometheusExometer.Convert do
  @moduledoc false

  # These functions convert values for output
  #
  # They are internal, exported only so that they can be accessed by tests

  # Add namespace and standard suffixes according to Prometheus conventions
  # Convert other metrics into standard format
  @spec convert_name(list(atom), Keyword.t, map) :: {list, list}
  def convert_name(name, info, %{converters: converters} = config) do
    convert_name(name, info, config, converters)
  end
  def convert_name(name, info, config) do
    convert_name(name, info, config, [])
  end

  # Default if no converter matches
  def convert_name(name, info, config, []) do
    options = info[:options]
    prometheus_options = options[:prometheus] || %{}
    namespace = config[:namespace] || []
    # Lager.debug("convert_name default #{inspect name} #{inspect info}")
    {namespace ++ name ++ suffix(prometheus_options), []}
  end
  def convert_name(name, info, config, [module | rest]) do
    options = info[:options]
    prometheus_options = options[:prometheus] || %{}
    namespace = config[:namespace] || []
    # Lager.debug("module #{module} name #{inspect name} options #{inspect options}")
    case module.prometheus_convert_name(name, options) do
      {new_name, labels} ->
        # Lager.debug("convert_name module #{module} #{inspect name} #{inspect new_name} #{inspect labels}")
        name = namespace ++ new_name ++ suffix(prometheus_options)
        {name, labels}
      _ ->
        convert_name(name, info, config, rest)
    end
  end

  # These functions have tests

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
