defmodule PrometheusExometer.Metrics do
  @moduledoc """
  Interface functions to update Exometer metrics with labels.

  The underlying [Exometer
  API](https://github.com/Feuerlabs/exometer_core/blob/master/doc/README.md#Setting_metric_values)
  to set values is simple. It doesn't change depending on the type of the
  metric, you can call the `update/3` function for everything. This function is a simple
  wrapper which calls `combine_name_labels/2` on its arguments, then calls
  `:exometer.update_or_create/2`. Calling e.g. `inc/3` if you are incrementing
  a counter makes the intent clearer, though.

  There are convenience functions to help with duration calculations as well.

  This interface largely implements the [recommended public API for Prometheus
  client libraries](https://prometheus.io/docs/instrumenting/writing_clientlibs/)

  Differences with the Prometheus API recommendations:

  Erlang handles times in microseconds internally, so that's what we store, and
  that's the default output unit instead of seconds.
  """

  @type name :: :exometer.name
  @type labels :: Keyword.t
  @type value :: any
  @type error :: {:error, any}

  # TODO: check that value is > 0 for counter

  @doc """
  Increment counter or gauge metric.

  Returns `:ok`.

  ## Examples

  Increment simple `requests` metric by one:

      iex> PrometheusExometer.Metrics.inc([:requests])
      :ok

  """
  @spec inc(name, labels, float) :: :ok
  def inc(name, labels, value) when is_list(labels) do
    update(name, labels, value)
  end

  @spec inc(name, labels) :: :ok
  def inc(name, labels) when is_list(labels), do: update(name, labels, 1)

  @spec inc(name, float) :: :ok
  def inc(name, value), do: update(name, name, value)

  @spec inc(name) :: :ok
  def inc(name), do: update(name, name, 1)

  @doc """
  Decrement counter or gauge metric.

  Returns `:ok`.

  ## Examples

      iex> PrometheusExometer.Metrics.dec([:active_requests])
      :ok

  """
  @spec dec(name, labels, float) :: :ok
  def dec(name, labels, value), do: update(name, labels, value)

  @spec dec(name, labels) :: :ok
  def dec(name, labels) when is_list(labels), do: update(name, labels, -1)

  @spec dec(name, float) :: :ok
  def dec(name, value), do: update(name, value)

  @spec dec(name) :: :ok
  def dec(name), do: update(name, -1)


  @doc """
  Set gauge to specified value.

  Returns `:ok`.

  ## Examples

      iex> PrometheusExometer.Metrics.set([:records], 1000)
      :ok

  """
  @spec set(list, labels, float) :: :ok
  def set(name, labels, value) when is_list(labels), do: update(name, labels, value)

  @spec set(name, float) :: :ok
  def set(name, value), do: update(name, value)

  @doc "Set metric to the current Unix time in seconds."
  @spec set_to_current_time(name, labels) :: :ok
  def set_to_current_time(name, labels) when is_list(labels), do: update(name, labels, unixtime())

  @spec set_to_current_time(name) :: :ok
  def set_to_current_time(name), do: update(name, unixtime())


  @doc """
  Set metric to the difference between the specified timestamp and the current time in ms.

  Returns `:ok`.

  ## Examples

      start_time = :os.timestamp()
      do_some_work()
      PrometheusExometer.Metrics.set_duration([:duration], start_time)

  """
  @spec set_duration(name, :erlang.timestamp) :: :ok
  def set_duration(name, start_time) do
    end_time = :os.timestamp()
    delta_time = :timer.now_diff(end_time, start_time)
    set(name, delta_time / 1)
  end

  @spec set_duration(name, labels, :erlang.timestamp) :: :ok
  def set_duration(name, labels, start_time) do
    end_time = :os.timestamp()
    delta_time = :timer.now_diff(end_time, start_time)
    set(name, labels, delta_time / 1)
  end


  # Prometheus standard API:
  # TODO:
  #
  # Floating point gauge values
  #
  # A gauge is ENCOURAGED to have:

  # A way to track in-progress requests in some piece of code/function.
  # This is track_inprogress in Python.

  # Histogram and Summary

  @doc "Observe current value for histogram or summary."
  @spec observe(name, labels, float) :: :ok | error
  def observe(name, labels, value) when is_list(labels) do
    # Prometheus standard API:
    # TODO: don't allow label of "le" or "quantile"
    # TODO: Validate name: ASCII letters and digits, underscores and colons.
    # Must match the regex [a-zA-Z_:][a-zA-Z0-9_:]*.
    # TODO: Label names may contain ASCII letters, numbers, as well as underscores.
    # They must match the regex [a-zA-Z_][a-zA-Z0-9_]*. Label names beginning with __ are reserved for internal use.

    update(name, labels, value)
  end

  @spec observe(name, value) :: :ok | error
  def observe(name, value), do: update(name, value)


  @doc "Observe time difference in ms between starting time and current time."
  @spec observe_duration(name, :erlang.timestamp) :: :ok | error
  def observe_duration(name, start_time) do
    end_time = :os.timestamp()
    delta_time = :timer.now_diff(end_time, start_time)
    observe(name, delta_time / 1)
  end

  @spec observe_duration(name, labels, :erlang.timestamp) :: :ok | error
  def observe_duration(name, labels, start_time) do
    end_time = :os.timestamp()
    delta_time = :timer.now_diff(end_time, start_time)
    observe(name, labels, delta_time / 1)
  end

  # TODO
  #
  # Summary
  # https://prometheus.io/docs/instrumenting/writing_clientlibs/#summary
  #
  # A summary MUST NOT allow the user to set "quantile" as a label name, as
  # this is used internally to designate summary quantiles.
  #
  # Histogram
  # https://prometheus.io/docs/instrumenting/writing_clientlibs/#histogram
  #
  # A histogram MUST NOT allow le as a user-set label, as le is used internally
  # to designate buckets.

  @doc "Update Exometer metric with labels"
  @spec update(name, labels, value) :: :ok | error
  def update(name, labels, value) do
    :exometer.update_or_create(combine_name_labels(name, labels), value)
  end
  @spec update(name, value) :: :ok | error
  def update(name, {labels, value} = tuple_value) when is_tuple(tuple_value) do
    :exometer.update_or_create(combine_name_labels(name, labels), value)
  end
  def update(name, value) do
    :exometer.update_or_create(name, value)
  end

  @doc "Get Exometer metric value"
  @spec get_value(name) :: {:ok, any} | {:error, :not_found}
  def get_value(name), do: :exometer.get_value(name)

  @doc "Get Exometer metric value with labels"
  @spec get_value(name, labels) :: {:ok, any} | {:error, :not_found}
  def get_value(name, labels) do
    :exometer.get_value(combine_name_labels(name, labels))
  end

  @doc "Ensure that a metric exists with the specified keyword under the parent metric"
  @spec ensure_child(name, labels) :: :ok | error
  def ensure_child(name, labels) do
    :exometer_admin.auto_create_entry(combine_name_labels(name, labels))
  end

  # @spec ensure_children(:exometer.name, list) :: :ok | {:error, any}
  # def ensure_children(name, labels_list) do
  #   for labels <- labels_list, do: ensure_child(name, labels)
  # end

  @doc "Combine base metric name with labels."
  @spec combine_name_labels(name, labels) :: name
  def combine_name_labels(name, labels) do
    # It's dangerous in general to convert to atoms,
    # but we have a small set which we control
    name ++ for {key, value} <- labels do
      String.to_atom("#{key}=\"#{value}\"")
    end
  end


  @doc "Record duration in ms of a function call, like Erlang :timer.tc/3"
  @spec tc(name, module, atom, list) :: any
  def tc(name, mod, fun, args) do
    {duration, value} = :timer.tc(mod, fun, args)
    observe(name, duration / 1)
    value
  end

  @spec tc(name, labels, module, atom, list) :: any
  def tc(name, labels, mod, fun, args) do
    {duration, value} = :timer.tc(mod, fun, args)
    observe(name, labels, duration / 1)
    value
  end

  # Utility
  defp unixtime do
    {mega, secs, _} = :os.timestamp()
    (mega * 1_000_000) + secs
  end

end
