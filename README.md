# prometheus_exometer

This library adds support to [Exometer](https://github.com/Feuerlabs/exometer_core)
to generate [Prometheus](https://prometheus.io/) metrics output. It reads the
Exometer metrics you define and generates a report in text format.

In a minimal system, you can set up a [Cowboy](https://github.com/ninenines/cowboy)
handler to respond to metrics requests, or you can add a route/endpoint to
[Phoenix](http://phoenixframework.org/).

This module supports the standard Exometer probe types such as counter,
as well as using [labels](https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels),
which is more natural for Prometheus, e.g.. 

    api_http_requests_total{method="POST", handler="/messages"}

It does this by converting the labels into keyword=value atoms which it appends to the
Exometer name, which is normally a list of atoms. You should not create a lot of different
labels, e.g. based on user input, as the Erlang VM has a relatively small fixed limit.

## Philosophy

The philosophy that we generally use is to record atom codes for handler,
action and detail on responses. The handler indicates the module which created
the response. The action is standard set like "success", "redirect",
"reject", "error" e.g. HTTP 200/300/400/500. Detail depends on the module,
e.g. if we reject DDOS traffic based on the HTTP user agent, it might be
"agent".

The result might look something like this for an API service:

    # HELP foo_responses Total number of responses
    # TYPE foo_responses counter
    api_responses{handler="rate_limit",action="reject",detail="ip"} 480
    api_responses{handler="validate",action="invalid",detail="user"} 7
    api_responses{handler="block_media",action="reject",detail="media"} 100
    api_responses{handler="db",action="invalid",detail="unknown"} 20
    api_responses{handler="route",action="redirect",detail="legacy"} 10
    api_responses{handler="api",action="success",detail="ok"} 1000


## Prometheus histograms vs Exometer historgrams 

There is a fundamental difference between Exometer histograms and Exometer histograms.
Exometer histogram buckets are dynamic, so when you get e.g. the 95% bucket, it depends
on the actual samples. Prometheus histograms have a static range, and are perhaps best
thought of as having multiple counters, one for each bucket. Because of this, we need
to pre-define the bucket ranges that we will use.   

## Installation

Add `prometheus_exometer` to your list of deps in `mix.exs`:

```elixir
def deps do
  [
    {:prometheus_exometer, github: "cogini/prometheus_exometer"},
  ]
end
```
This will pull in Exometer and its dependencies as well.

Configure Exometer to use the custom
[probes](https://github.com/Feuerlabs/exometer_core/blob/master/doc/README.md#Built-in_entries_and_probes)
defined in this module, e.g. in `config/config.exs`. 

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
`predefined` section of the `exometer_core` config generally works best if possible. 

In order to make things more resilent during development, the metrics recording
functions in this library call `:exometer.update_or_create/2`. The effect is
that the metric will be created the first time it is used, but it will use the
settings in the `defaults` section of the `exometer_core` config. 

If you have specific settings that you want, e.g. histogram buckets, then you
should define the metric before you use it, either in the `predefined` section
or in your application initialization. 

