defmodule PrometheusExometer.SampleMetrics do
  @moduledoc "Collect metrics by calling functions"

  use GenServer

  @doc "Start the sampler server"
  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init(args) do
    sample_interval = args[:sample_interval] || 60_000
    {:ok, _timer} = :timer.send_interval(sample_interval, :sample_metrics)

    state = %{
      metrics: args[:metrics] || []
    }
    {:ok, state}
  end

  @impl true
  def handle_info(:sample_metrics, state) do
    Enum.each(state.metrics,
              fn
                {metric, {m, f, a}} ->
                  PrometheusExometer.Metrics.observe(metric, apply(m, f, a))
                {metric, labels, {m, f, a}} ->
                  PrometheusExometer.Metrics.observe(metric, labels, apply(m, f, a))
              end)
    {:noreply, state}
  end

end
