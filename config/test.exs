use Mix.Config

config :exometer_core,
  defaults: [
    {[:_], :history, [module: :exometer_folsom]},
    {[:_], :prometheus_counter, [module: :prometheus_exometer_counter]},
    {[:_], :prometheus_gauge, [module: :prometheus_exometer_gauge]},
    {[:_], :prometheus_histogram,
     [
       module: :prometheus_exometer_histogram,
       options: [
         time_span: 300_000,
         truncate: false,
         histogram_module: :exometer_slide,
         keep_high: 100,
         prometheus: %{export_buckets: true}
       ]
     ]},
    {[:_], :histogram,
     [
       module: :exometer_histogram,
       options: [
         time_span: 300_000,
         truncate: false,
         histogram_module: :exometer_slide,
         keep_high: 100,
         prometheus: %{export_quantiles: true}
       ]
     ]}
  ],
  predefined: [
    {[:duration], :prometheus_histogram,
     [
       prometheus: %{
         description: "Time to create response",
         unit: :us,
         suffix: :us,
         export_buckets: true,
         buckets: [
           100,
           250,
           500,
           750,
           1000,
           5000,
           10_000,
           25_000,
           50_000,
           75_000,
           100_000,
           500_000,
           750_000,
           1_000_000,
           1_500_000,
           2_000_000,
           2_100_000,
           2_500_000
         ]
       }
     ]},
    {[:requests], :prometheus_counter, [prometheus: %{description: "Total number of requests"}]},
    {[:responses], :prometheus_counter, [prometheus: %{description: "Total number of responses"}]}
  ]
