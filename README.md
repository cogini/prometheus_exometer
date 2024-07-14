# prometheus_exometer

This library adds support to [Exometer](https://github.com/Feuerlabs/exometer_core)
to generate [Prometheus](https://prometheus.io/) metrics output. It reads the
Exometer metrics you define and generates a report in text format.

In a minimal system, you can set up a [Cowboy](https://github.com/ninenines/cowboy)
handler to respond to metrics requests, or you can add a route/endpoint to
[Phoenix](http://phoenixframework.org/).

This module supports the standard Exometer probe types such as counter,
as well as using [labels](https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels),
which is more natural for Prometheus, e.g.:

    api_http_requests_total{method="POST", handler="/messages"}

It does this by converting the labels into keyword=value atoms which it appends
to the Exometer name, which is normally a list of atoms. The Erlang VM has a
relatively small fixed limit on the number of atoms. Because of this, you
should not create labels in response to external input, you should limit the
atoms to a relatively small set that you control.

## Example

An example of creating metrics is to record atom codes for handler, action, and
detail on responses. The handler indicates the module which created the
response. The action is a standard set like "success", "redirect", "reject",
"error", similar to HTTP 200/300/400/500 responses. Detail depends on the
module, e.g. if we reject DDOS traffic based on the HTTP user agent, it might
be "agent.

The result might look something like this for an API service:

    # HELP api_responses Total number of responses
    # TYPE api_responses counter
    api_responses{handler="rate_limit",action="reject",detail="ip"} 480
    api_responses{handler="validate",action="invalid",detail="user"} 7
    api_responses{handler="block_media",action="reject",detail="media"} 100
    api_responses{handler="db",action="invalid",detail="unknown"} 20
    api_responses{handler="route",action="redirect",detail="legacy"} 10
    api_responses{handler="api",action="success",detail="ok"} 1000

## Prometheus histograms vs Exometer histograms

There is a fundamental difference between Exometer histograms and Prometheus
histograms. Exometer histogram buckets are dynamic, so when you get e.g., the
95% bucket, it depends on the actual samples. Prometheus histograms have a
static range, and are perhaps best thought of as having multiple counters, one
for each bucket. Because of this, we need to predefine the bucket ranges that
we will use.

## Installation

Add `prometheus_exometer` to your list of deps in `mix.exs`:

```elixir
def deps do
  [
    {:prometheus_exometer, github: "cogini/prometheus_exometer"},
  ]
end
```
This will pull in Exometer and its dependencies.

Configure Exometer to use the custom
[probes](https://github.com/Feuerlabs/exometer_core/blob/master/doc/README.md#Built-in_entries_and_probes)
defined in this module, e.g., in `config/config.exs`.

```elixir
config :exometer_core,
  defaults: [
    {[:_], :history, [module: :exometer_folsom]},
    {[:_], :prometheus_counter, [module: :prometheus_exometer_counter]},
    {[:_], :prometheus_gauge, [module: :prometheus_exometer_gauge]},
    {[:_], :prometheus_histogram, [module: :prometheus_exometer_histogram,
      options: [time_span: 300_000, truncate: :false, histogram_module: :exometer_slide, keep_high: 100,
                prometheus: %{export_buckets: :true}
               ],
    ]},
    {[:_], :histogram, [module: :exometer_histogram,
      options: [time_span: 300_000, truncate: :false, histogram_module: :exometer_slide, keep_high: 100,
                prometheus: %{export_quantiles: :true}
              ],
    ]},
  ],
  predefined: [
    {[:duration], :prometheus_histogram, [prometheus: %{
        description: "Time to create response",
        unit: :us, suffix: :us, export_buckets: :true,
        buckets: [100, 250, 500, 750, 1000, 5000, 10_000, 25_000, 50_000, 75_000, 100_000,
                  500_000, 750_000, 1_000_000, 1_500_000, 2_000_000, 2_100_000, 2_500_000],
    }]},
    {[:requests], :prometheus_counter, [prometheus: %{description: "Total number of requests"}]},
    {[:responses], :prometheus_counter, [prometheus: %{description: "Total number of responses"}]},
  ]
```

## Defining metrics

While it's possible to define Exometer metrics programmatically in your code,
due to the loose relationship between independent Erlang applications, it's
easy to get into race conditions on startup. Defining metrics is in
`predefined` section of the `exometer_core` config generally works well, though
the syntax is a bit messy.

In order to make things more resilient, the metrics recording functions in this
library call `:exometer.update_or_create/2`. The effect is that the metric will
be created the first time it is used based on the settings in the
`defaults` section of the `exometer_core` config.

If you have specific settings that you want, e.g., histogram buckets, then you
should define the metric before you use it, either in the `predefined` section
or in your application initialization.

Following is an example Cowboy "middleware" that uses an init function to
create metrics. It uses the low level `:exometer.update/2`, since it knows that
the metrics are there, though `PrometheusMiddleware.Metrics.update/2` would
work as well.

```elixir
defmodule Foo.Middleware do
  @moduledoc "Cowboy middleware which records metrics"
  require Logger

  alias PrometheusMiddleware.Metrics

  @behaviour :cowboy_middleware

  @metric_http_requests [:cowboy, :http, :requests]
  @metric_http_responses [:cowboy, :http, :responses]
  @metric_http_active [:cowboy, :http, :active]
  @metric_http_errors [:cowboy, :http, :errors]
  @metric_http_duration [:cowboy, :http, :duration]

  # https://en.wikipedia.org/wiki/List_of_HTTP_status_codes
  @status_codes [200, 201, 202, 203, 204, 205, 206,
                 300, 301, 302, 303, 304, 305, 306, 307, 308,
                 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410,
                 411, 412, 413, 414, 415, 416, 417, 418, 419, 421, 426,
                 428, 429, 431, 451,
                 500, 501, 502, 503, 504, 505, 506, 511]

  # Called once by Cowboy on startup
  def init do
    # Logger.debug("Creating Exometer metrics")
    :ok = :exometer.ensure(@metric_http_requests, :counter, prometheus: %{
                             description: "Total http requests"
                           })

    :ok = :exometer.ensure(@metric_http_responses, :prometheus_counter, prometheus: %{
                             description: "Total responses by code"
                           })

    # Create metrics for each of the status codes
    # TODO: the code is actually a string, e.g., "200 OK", so this doesn't really work
    for code <- @status_codes do
      Metrics.ensure_child(@metric_http_responses, code: code)
    end

    :ok = :exometer.ensure(@metric_http_errors, :counter, prometheus: %{
                             description: "Total errors (5xx)"
                           })

    :ok = :exometer.ensure(@metric_http_invalid_qs, :counter, prometheus: %{
                             description: "Total requests with invalid query string"

    # This is a counter instead of a guage to get atomic increment/decrement
    # semantics. It's not accurate in the case of Cowboy, as the hook functions don't get
    # called in case of errors, but is here as an example of how to use the metrics functions.
    :ok = :exometer.ensure(@metric_http_active, :counter, prometheus: %{
                             description: "Instantaneous active requests",
                             type: :gauge
                           })

    :ok = :exometer.ensure(@metric_http_duration, :prometheus_histogram,
                           prometheus: %{
                             description: "Total processing duration",
                             unit: :us, suffix: :us,
                             export_buckets: :true,
                             buckets: [100, 250, 500, 750, 1000, 5000,
                                       10_000, 25_000, 50_000, 75_000,
                                       100_000, 500_000, 750_000, 1_000_000,
                                       1_500_000, 2_000_000, 2_100_000],
                           },
                           time_span: 300_000, truncate: false)

    :ok
  end

  # Called at start of valid request
  # It will not be called on e.g., HTTP parse errors, though the response hook will be
  def execute(req, env) do
    # Logger.debug("execute: #{inspect req} #{inspect env}")
    :exometer.update(@metric_http_requests, 1)
    :exometer.update(@metric_http_active, 1)

    # Set start time of the request
    req = :cowboy_req.set_meta(:foo_start_time, :os.timestamp(), req)

    {:ok, req, env}
  end

  # Called at end of request
  def cowboy_response_hook(code, headers, body, req) do
    # code may be an integer or a string like "200 OK"
    code = get_code(code)

    :exometer.update(@metric_http_responses, {[code: code], 1})

    if code >= 500 and code < 600 do
      :exometer.update(@metric_http_errors, 1)
    end

    {start_time, req} = :cowboy_req.meta(:foo_start_time, req)
    case start_time do
      :undefined -> :ok

      _ ->
        Metrics.observe_duration(@metric_http_duration, start_time)
        :exometer.update(@metric_http_active, -1)
    end
    # Logger.debug("cowboy_response_hook: end #{code} #{inspect req2} #{inspect stats()}")

    # Pretend to be Nginx
    headers2 = :lists.keyreplace("server", 1, headers, {"server", "nginx"})
    {:ok, req} = :cowboy_req.reply(code, headers2, body, req)
    req
  end

  @spec get_code(non_neg_integer | binary) :: non_neg_integer
  defp get_code(code) when is_integer(code), do: code
  defp get_code(code) when is_binary(code) do
    # code may be string like "200 OK"
    code = hd(String.split(code))
    String.to_integer(code)
  end

end
```

```
# HELP api_cowboy_http_active Instantaneous active requests
# TYPE api_cowboy_http_active gauge
api_cowboy_http_active 0
# HELP api_cowboy_http_duration_us Total processing duration
# TYPE api_cowboy_http_duration_us histogram
api_cowboy_http_duration_us{le="100"} 0
api_cowboy_http_duration_us{le="250"} 0
api_cowboy_http_duration_us{le="500"} 0
api_cowboy_http_duration_us{le="750"} 0
api_cowboy_http_duration_us{le="1000"} 0
api_cowboy_http_duration_us{le="5000"} 0
api_cowboy_http_duration_us{le="10000"} 32
api_cowboy_http_duration_us{le="25000"} 77
api_cowboy_http_duration_us{le="50000"} 78
api_cowboy_http_duration_us{le="75000"} 78
api_cowboy_http_duration_us{le="100000"} 78
api_cowboy_http_duration_us{le="500000"} 103
api_cowboy_http_duration_us{le="750000"} 107
api_cowboy_http_duration_us{le="1000000"} 107
api_cowboy_http_duration_us{le="1500000"} 107
api_cowboy_http_duration_us{le="2000000"} 107
api_cowboy_http_duration_us{le="2100000"} 107
api_cowboy_http_duration_us{le="+Inf"} 107
api_cowboy_http_duration_us_sum 13563467
api_cowboy_http_duration_us_count 107
# HELP api_cowboy_http_errors Total errors (5xx)
# TYPE api_cowboy_http_errors counter
api_cowboy_http_errors 0
# HELP api_cowboy_http_requests Total http requests
# TYPE api_cowboy_http_requests counter
api_cowboy_http_requests 107
# HELP api_cowboy_http_responses Total responses by code
# TYPE api_cowboy_http_responses counter
api_cowboy_http_responses 0
api_cowboy_http_responses{code="200 OK"} 49
api_cowboy_http_responses{code="302 Found"} 48
api_cowboy_http_responses{code="404 Not Found"} 10
```

# Sampling metrics

`PrometheusExometer.SampleMetrics` is a GenServer that periodically updates
metrics by calling functions.

Put this in `config/config.exs`:

```elixir
config :foo,
  sample_metrics: [
    sample_interval: 60_000,
    metrics: [
      {[:erlang, :memory, :total], {:erlang, :memory, [:total]}},
      {[:erlang, :memory, :processes], {:erlang, :memory, [:processes]}},
      {[:erlang, :memory, :processes_used], {:erlang, :memory, [:processes_used]}},
      {[:erlang, :memory, :system], {:erlang, :memory, [:system]}},
      {[:erlang, :memory, :atom], {:erlang, :memory, [:atom]}},
      {[:erlang, :memory, :atom_used], {:erlang, :memory, [:atom_used]}},
      {[:erlang, :memory, :binary], {:erlang, :memory, [:binary]}},
      {[:erlang, :memory, :ets], {:erlang, :memory, [:ets]}},
      {[:erlang, :system_info, :process_count], {:erlang, :system_info, [:process_count]}},
      {[:erlang, :system_info, :port_count], {:erlang, :system_info, [:port_count]}},
      {[:erlang, :statistics, :run_queue], {:erlang, :statistics, [:run_queue]}},
    ]
  ]

config :foo,
  exometer_predefined: [
      {[:erlang, :memory, :total], :gauge, []},
      {[:erlang, :memory, :processes], :gauge, []},
      {[:erlang, :memory, :processes_used], :gauge, []},
      {[:erlang, :memory, :system], :gauge, []},
      {[:erlang, :memory, :atom], :gauge, []},
      {[:erlang, :memory, :atom_used], :gauge, []},
      {[:erlang, :memory, :binary], :gauge, []},
      {[:erlang, :memory, :ets], :gauge, []},
      {[:erlang, :system_info, :process_count], :gauge, []},
      {[:erlang, :system_info, :port_count], :gauge, []},
      {[:erlang, :statistics, :run_queue], :gauge, []},
  ]
```

Configure and start it in your application supervisor:

```elixir
def start(_type, _args) do
  import Supervisor.Spec

  sample_metrics_opts = Application.get_env(:foo, :sample_metrics, [])

  children = [
    {PrometheusExometer.SampleMetrics, [sample_metrics_opts]},
  ]

  opts = [strategy: :one_for_one, name: Foo.Supervisor]
  Supervisor.start_link(children, opts)
end
```
