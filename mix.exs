defmodule PrometheusExometer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :prometheus_exometer,
      version: "0.1.0",
      elixir: "> 1.4.0",
      start_permanent: Mix.env == :prod,
      dialyzer: [
        plt_add_deps: true,
        # flags: ["-Wunmatched_returns", :error_handling, :race_conditions, :underspecs],
      ],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # extra_applications: [:lager, :logger]
      extra_applications: [:lager]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false},
      {:exlager, github: "reachfh/exlager", branch: "metadata"},
      {:exometer_core, github: "Feuerlabs/exometer_core", tag: "1.5.0"},
      {:setup, github: "uwiger/setup", manager: :rebar, override: true}, # fix for https://github.com/uwiger/setup/issues/24
      # {:mix_test_watch, "~> 0.5", only: :dev, runtime: false},
    ]
  end
end
