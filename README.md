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
defined in this module. 

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
