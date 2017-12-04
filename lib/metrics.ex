defmodule PrometheusExometer.Metrics do
  @moduledoc """
  API to record metrics

  This implements the [recommended public API for Prometheus client 
  libraries](https://prometheus.io/docs/instrumenting/writing_clientlibs/)

  They underlying Exometer API is pretty straightforward, though, so it
  is possible to just call the generic `update` API. 

  Differences with the Prometheus API recommendations: 

  Erlang times are in microseconds internally, so that's what we store,
  and that's the default output unit instead of seconds.
  
  """
  require Lager

  # TODO: check that value is > 0 for counter
  @type name :: :exometer.name
  @type labels :: Keyword.t
  @type value :: any
  @type error :: {:error, any}

  @doc "Increment counter or gauge"
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

  @doc "Increment gauge"
  @spec dec(name, labels, float) :: :ok
  def dec(name, labels, value), do: update(name, labels, value)

  @spec dec(name, labels) :: :ok
  def dec(name, labels) when is_list(labels), do: update(name, labels, -1)

  @spec dec(name, float) :: :ok
  def dec(name, value), do: update(name, value)

  @spec dec(name) :: :ok
  def dec(name), do: update(name, -1)

  @doc "Set gauge to value"
  @spec set(list, labels, float) :: :ok
  def set(name, labels, value) when is_list(labels), do: update(name, labels, value)

  @spec set(name, float) :: :ok
  def set(name, value), do: update(name, value)

  @doc "Set gauge to the current unixtime in seconds"
  @spec set_to_current_time(name, labels) :: :ok
  def set_to_current_time(name, labels) when is_list(labels), do: update(name, labels, unixtime())

  @spec set_to_current_time(name) :: :ok
  def set_to_current_time(name), do: update(name, unixtime())

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


  # TODO:
  #
  # Floating point gauge values
  #
  # A gauge is ENCOURAGED to have:

  # A way to track in-progress requests in some piece of code/function.
  # This is track_inprogress in Python.

  # Histogram and Summary

  @doc "Observe current value for histogram or summary"
  @spec observe(name, labels, float) :: :ok | error
  def observe(name, labels, value) when is_list(labels) do
    # TODO: don't allow label of "le" or "quantile"
    # TODO: Validate name: ASCII letters and digits, underscores and colons.
    # Must match the regex [a-zA-Z_:][a-zA-Z0-9_:]*.
    # TODO: Label names may contain ASCII letters, numbers, as well as underscores.
    # They must match the regex [a-zA-Z_][a-zA-Z0-9_]*. Label names beginning with __ are reserved for internal use.

    update(name, labels, value)
  end

  @spec observe(name, value) :: :ok | error
  def observe(name, value), do: update(name, value)

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

  @doc "Generic Exometer public interface which handles labels"

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

  @spec get_value(name) :: {:ok, any} | {:error, :not_found}
  def get_value(name) do
    :exometer.get_value(name)
  end

  @spec get_value(name, labels) :: {:ok, any} | {:error, :not_found}
  def get_value(name, labels) do
    :exometer.get_value(combine_name_labels(name, labels))
  end

  @doc "Ensure that a metric exists with the specified keyword under the parent metric"
  @spec ensure_child(name, labels) :: :ok | error
  def ensure_child(name, labels) do
    :exometer_admin.auto_create_entry(combine_name_labels(name, labels))
  end

  # Just a wrapper on :exometer.ensure
  # @doc "Ensure that metric exists and is of given type"
  # @spec ensure(:exometer.name, :exometer.type) :: :ok | {:error, any}
  # def ensure(name, type), do: :exometer.ensure(name, type, [])

  # @spec ensure(:exometer.name, :exometer.type, :exometer.options) :: :ok | {:error, any}
  # def ensure(name, type, options), do: :exometer.ensure(name, type, options)

  # Unused, it seems
  # @spec ensure_children(:exometer.name, list) :: :ok | {:error, any}
  # def ensure_children(name, labels_list) do
  #   for labels <- labels_list, do: ensure_child(name, labels)
  # end

  @doc "Combine base metric name with labels"
  @spec combine_name_labels(name, labels) :: name
  def combine_name_labels(name, labels) do
    # It's dangerous in general to convert to atoms,
    # but we have a small set which we control
    name ++ for {key, value} <- labels do
      String.to_atom("#{key}=\"#{value}\"")
    end
  end

  @doc "Record duration in ms of a function call, like :timer.tc"
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
