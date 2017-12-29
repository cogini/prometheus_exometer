defmodule PrometheusExometer do
  @moduledoc """
  Interface functions to publish Exometer metrics in Prometheus format.

  The primary interface is `scrape/1`.

  """

  alias PrometheusExometer.FormatText

  # require Lager

  @doc "Get modules which have a prometheus_convert_name callback defined"
  @spec get_converters(list(module)) :: list(module)
  def get_converters([]), do: []
  def get_converters(modules) do
    Enum.filter(modules, fn(module) ->
      exports = module.module_info(:exports)
      Keyword.has_key?(exports, :prometheus_convert_name)
    end)
  end

  @doc """
  Format data from Exometer metrics in Prometheus text format.

  It takes a map with configuration options.

  config = %{namespace: list(atom), converters: list(module)}

  It has two keys:

  - namespace: a prefix which will be added to each metric, normally the app name
  - converters: a list of modules which have callback functions to convert
      internal Exometer names into external format

  """
  @spec scrape(map) :: iolist
  def scrape(config) do
    start_time = :os.timestamp()

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
      FormatText.format_entry(value, config)
    end)

    # {results, _names_seen} = List.foldl(entries, {[], %{}}, &format_entry/2)
    [results, FormatText.format_scrape_duration(config, start_time), FormatText.format_namespace_up(config)]
  end

  @doc "Scrape with default config"
  @spec scrape() :: iolist
  def scrape, do: scrape(%{})

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

end
