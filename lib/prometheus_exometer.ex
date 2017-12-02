defmodule PrometheusExometer do
  @moduledoc false

  require Lager

  @app :bounce

  @doc "Initialize metrics from modules"
  def init do
    modules = Application.get_env(@app, :prometheus_modules, [])
    Enum.each(modules, fn(module) ->
      exports = module.module_info(:exports)
      if Keyword.has_key?(exports, :prometheus_init) do
        # Lager.error("#{module}.prometheus_init")
        module.prometheus_init([])
      end
    end)
  end

  @doc "Get modules which have a name converter callback defined"
  @spec get_name_converters(list(module)) :: list(module)
  def get_name_converters([]), do: []
  def get_name_converters(modules) do
    Enum.filter(modules, fn(module) ->
      exports = module.module_info(:exports)
      Keyword.has_key?(exports, :prometheus_convert_name)
    end)
  end

  @doc """
  Get metric data in Prometheus format
  This is called by the HTTP endpoint
  """
  @spec scrape(list(atom), list(module)) :: iodata
  def scrape(namespace, modules)  do
    start_time = :os.timestamp()

    converters = get_name_converters(modules)
    config = %{namespace: namespace, converters: converters}

    entries = :exometer.find_entries([:_])
    entries = Enum.sort(entries)
    # Lager.debug("entries: #{inspect entries, pretty: true, limit: 30_000}")

    entry_info = List.foldl(entries, %{}, &collect_children/2)
    entry_keys = entry_info
                 |> Map.keys()
                 |> Enum.sort()

    results = Enum.flat_map(entry_keys, fn(name) ->
      value = entry_info[name]
      # Lager.debug("name: #{inspect name} #{inspect value.info}")
      # Enum.each(value.children, &(Lager.debug("children: #{inspect &1, pretty: true}")))
      format_entry(value, config)
    end)

    # {results, _names_seen} = List.foldl(entries, {[], %{}}, &format_entry/2)
    [results, format_scrape_duration(namespace, start_time), format_namespace_up(namespace)]
  end

  defp collect_children({exometer_name, exometer_type, :enabled}, parents) do
    info = :exometer.info(exometer_name)
    options = info[:options]
    prometheus_options = options[:prometheus] || %{}
    case Map.fetch(prometheus_options, :parent) do
      :error ->
        # Parent or simple metric
        # Lager.debug("parent #{inspect exometer_name} info #{inspect info}")
        Map.put(parents, exometer_name, %{info: info, children: []})
      {:ok, parent_name} ->
        # Child, may also be a parent if it's a composite type
        # Lager.debug("child #{inspect exometer_name} info #{inspect info}")
        if exometer_type in [:prometheus_counter, :prometheus_gauge, :prometheus_histogram] do
          # parents = Map.put(parents, exometer_name, %{info: info, children: []})
          update_in(parents[parent_name][:children], &(&1 ++ [info]))
        else
          if Map.has_key?(prometheus_options, :internal) do
            parents
          else
            update_in(parents[parent_name][:children], &(&1 ++ [info]))
          end
        end
    end
  end
  defp collect_children({_, _, _}, acc) do
    # Skip disabled entries
    acc
  end

  defp format_entry(entry, config) do
    # Everything here is a prometheus parent or generic Exometer entry
    info = entry.info
    options = info[:options]
    prometheus_options = options[:prometheus] || %{}
    exometer_name = info[:name]
    exometer_type = info[:type]

    {name, name_labels} = split_name_labels(exometer_name, prometheus_options)
    {name, converted_labels} = convert_name(name, info, config)
    labels = name_labels ++ converted_labels

    [
      format_header(name, labels, prometheus_options, exometer_name, exometer_type),
      format_data(name, labels, exometer_name, exometer_type, prometheus_options),
      for child <- entry.children do format_child(child, name, converted_labels) end
    ]
  end

  defp format_child(info, parent_name, parent_labels) do
    options = info[:options]
    prometheus_options = options[:prometheus] || %{}
    exometer_name = info[:name]
    exometer_type = info[:type]

    {_name, labels} = split_name_labels(exometer_name, prometheus_options)
    format_data(parent_name, parent_labels ++ labels, exometer_name, exometer_type, prometheus_options)
  end

  defp format_data(name, labels, exometer_name, :prometheus_histogram, prometheus_options) do
    # [{sum: 0.0}, {:count, 0.0}, {50, "50}, {75, "75"}, {90, "90"}, {95, "95"}, {inf, "+Inf"}]
    {:ok, data_points} = :exometer.get_value(exometer_name)
    # Lager.debug("data_points: #{inspect data_points}")

    [
      if Map.get(prometheus_options, :export_buckets, false) do
        for {k, v} <- data_points, not k in [:ms_since_reset, :sum, :count] do
          format_data(name, labels ++ ["le=\"#{k}\""], v)
        end
      else
        []
      end,
      format_data(name ++ [:sum], labels, convert_unit(prometheus_options, data_points[:sum])),
      format_data(name ++ [:count], labels, data_points[:count])
    ]
  end

  defp format_data(name, labels, exometer_name, :histogram, prometheus_options) do
    # [{:n, 0.0}, {:mean, 0.0}, {:min, 0.0}, {:max, 0.0}, {:median, 0.0},
    # {50, 0.0}, {75, 0.0}, {90, 0.0}, {95, 0.0}, {99, 0.0}, {999, 0.0}]}
    {:ok, data_points} = :exometer.get_value(exometer_name)
    # Lager.debug("data_points: #{inspect data_points}")
    n = data_points[:n]
    [
      format_data(name ++ [:sum], labels, convert_unit(prometheus_options, data_points[:mean] * n)),
      format_data(name ++ [:count], labels, n),
      if Map.get(prometheus_options, :export_quantiles, false) do
        for {k, q} <- [{50, "0.5"}, {75, "0.75"}, {90, "0.9"}, {95, "0.95"}, {99, "0.99"}, {999, "0.999"}] do
          {_k, v} = List.keyfind(data_points, k, 0)
          format_data(name, labels ++ [{:quantile, q}], v)
        end
      else
       []
      end
    ]
  end

  defp format_data(name, labels, exometer_name, exometer_type, prometheus_options)
    when exometer_type in [:counter, :prometheus_counter] do

    # [{:value, 0}, {:ms_since_reset, 15615}]
    {:ok, data_points} = :exometer.get_value(exometer_name)
    [
      format_data(name, labels, convert_unit(prometheus_options, data_points[:value]))
    ]
  end

  defp format_data(name, labels, exometer_name, exometer_type, prometheus_options)
    when exometer_type in [:gauge, :prometheus_gauge] do

    # [value: 0, ms_since_reset: 15615]
    {:ok, data_points} = :exometer.get_value(exometer_name)
    [
      format_data(name, labels, convert_unit(prometheus_options, data_points[:value]))
    ]
  end

  defp format_data(name, labels, exometer_name, :meter, prometheus_options) do
    # [count: 0, one: 0, five: 0, fifteen: 0, day: 0, mean: 0,
    # acceleration: [one_to_five: 0.0, five_to_fifteen: 0.0, one_to_fifteen: 0.0]]
    {:ok, data_points} = :exometer.get_value(exometer_name)
    [
      # TODO: make sure this is the right value to read; are other values interesting
      # should we use data format https://github.com/boundary/folsom
      format_data(name, labels, convert_unit(prometheus_options, data_points[:one]))
    ]
  end
  defp format_data(name, labels, exometer_name, exometer_type, prometheus_options) do
    Lager.debug("Skipping #{inspect name} #{inspect labels} #{inspect exometer_name} #{inspect exometer_type} #{inspect prometheus_options}")
    []
  end


  # Add namespace and standard suffixes according to Prometheus conventions
  # Convert other metrics into standard format
  defp convert_name(name, info, config) do
    convert_name(name, info, config, config.converters)
  end

  # Default if no converter matches
  defp convert_name(name, info, config, []) do
    options = info[:options]
    prometheus_options = options[:prometheus] || %{}
    # Lager.debug("convert_name default #{inspect name} #{inspect info}")
    {config.namespace ++ name ++ suffix(prometheus_options), []}
  end
  defp convert_name(name, info, config, [module | rest]) do
    options = info[:options]
    prometheus_options = options[:prometheus] || %{}
    # Lager.debug("module #{module} name #{inspect name} options #{inspect options}")
    case module.prometheus_convert_name(name, options) do
      {new_name, labels} ->
        # Lager.debug("convert_name module #{module} #{inspect name} #{inspect new_name} #{inspect labels}")
        name = config.namespace ++ new_name ++ suffix(prometheus_options)
        {name, labels}
      _ ->
        convert_name(name, info, config, rest)
    end
  end

  ### tested

  @spec format_names(list) :: iodata
  def format_names(names) when is_list(names) do
    names = for name <- names, do: to_string(name)
    Enum.intersperse(names, "_")
  end

  @spec format_value(term) :: iodata
  def format_value(value) when is_float(value), do: to_string(Float.round(value, 4))
  def format_value(value), do: to_string(value)

  @spec format_help(list(atom), String.t) :: iodata
  def format_help(names, description) when is_binary(description) do
    ["# HELP ", format_names(names), " ", description, "\n"]
  end

  @spec format_type(list(atom), String.t) :: iodata
  def format_type(names, type_name) when is_binary(type_name) do
    ["# TYPE ", format_names(names), " ", type_name, "\n"]
  end

  @spec format_description(Map.t | nil, :exometer.name) :: iodata
  def format_description(prometheus_options, exometer_name)
  def format_description(%{description: description}, _) when is_binary(description), do: description
  def format_description(_prometheus_options, exometer_name), do: inspect(exometer_name)

  @spec format_label(binary | atom | tuple) :: iodata
  def format_label(label) when is_binary(label), do: label
  def format_label(label) when is_atom(label), do: to_string(label)
  def format_label({key, value} = label) when is_tuple(label), do: [to_string(key), "=\"", to_string(value), "\""]

  @spec format_labels(list(atom)) :: iodata
  def format_labels([]), do: ""
  def format_labels(labels) do
    label_strings = Enum.map(labels, &format_label/1)
    Enum.intersperse(label_strings, ",")
  end

  @spec format_metric(list, list) :: iodata
  def format_metric(names, []), do: format_names(names)
  def format_metric(names, labels), do: [format_names(names), "{", format_labels(labels), "}"]

  @spec format_data(list(atom), Keyword.t, term) :: iodata
  def format_data(names, labels, value) do
    [format_metric(names, labels), " ", format_value(value), "\n"]
  end

  @spec format_type_name(map | nil, atom) :: String.t
  def format_type_name(prometheus_options, exometer_type)
  def format_type_name(%{type: type}, _exometer_type), do: format_type_name(type)
  def format_type_name(_, exometer_type),              do: format_type_name(exometer_type)

  @spec format_type_name(atom) :: String.t
  def format_type_name(exometer_type)
  def format_type_name(:prometheus_counter), do: "counter"
  def format_type_name(:prometheus_gauge), do: "gauge"
  def format_type_name(:prometheus_histogram), do: "histogram"
  def format_type_name(:counter), do: "counter"
  def format_type_name(:gauge), do: "gauge"
  def format_type_name(:meter), do: "counter"
  def format_type_name(:spiral), do: "gauge"
  def format_type_name(:histogram), do: "summary"
  def format_type_name(_), do: "untyped"


  @doc "Format scrape duration metric"
  @spec format_scrape_duration(list(atom), :erlang.timestamp) :: iodata
  def format_scrape_duration(prefix, start_time) do
    duration = :timer.now_diff(:os.timestamp(), start_time) / 1_000_000
    format_data(prefix ++ [:scrape_duration_seconds], [], duration)
  end

  @doc "Format up metric"
  @spec format_namespace_up(list) :: iodata
  def format_namespace_up([]), do: []
  def format_namespace_up(namespace) when is_list(namespace) do
    format_data(namespace ++ ["up"], [], 1)
  end


  @doc "Format metric header"
  @spec format_header(:exometer.name, list, map, :exometer.name, atom) :: iodata
  def format_header(name, labels, prometheus_options, exometer_name, exometer_type)
  def format_header(name, [], prometheus_options, exometer_name, exometer_type) do
    [
      format_help(name, format_description(prometheus_options, exometer_name)),
      format_type(name, format_type_name(prometheus_options, exometer_type)),
    ]
  end
  def format_header(_, _, _, _, _), do: []


  @spec convert_unit(map, term) :: term
  def convert_unit(prometheus_options, value)
  def convert_unit(%{unit: from, export_unit: to}, value), do: convert_unit(from, to, value)
  def convert_unit(_, value), do: value

  @spec convert_unit(atom, atom, term) :: term
  def convert_unit(from, to, value)
  def convert_unit(:us, :seconds, value), do: value / 1_000_000
  def convert_unit(_, _, value), do: value

  @spec suffix(Map.t) :: list
  def suffix(prometheus_options)
  def suffix(%{suffix: suffix}) when is_list(suffix), do: suffix
  def suffix(%{suffix: suffix}), do: [suffix]
  def suffix(_), do: []

  @doc "Separate name and labels from Exometer name"
  @spec split_name_labels(:exometer.name, Map.t) :: {:exometer.name, list}
  def split_name_labels(exometer_name, %{parent: parent}), do: {parent, strip_prefix(parent, exometer_name)}
  def split_name_labels(exometer_name, _options), do: {exometer_name, []}

  @spec strip_prefix(list, list) :: list
  def strip_prefix([head | rest1], [head | rest2]), do: strip_prefix(rest1, rest2)
  def strip_prefix([], labels), do: labels

end
