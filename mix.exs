defmodule PrometheusExometer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :prometheus_exometer,
      version: "0.1.0",
      elixir: ">= 1.5.0",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      description: description(),
      package: package(),
      source_url: "https://github.com/cogini/prometheus_exometer",
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
      # extra_applications: [:lager]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false},
      # {:exlager, github: "khia/exlager"},
      # {:exometer_core, github: "Feuerlabs/exometer_core", tag: "1.5.0"},
      {:exometer_core, "~> 1.5"},
      {:setup, github: "uwiger/setup", manager: :rebar, override: true}, # fix for https://github.com/uwiger/setup/issues/24
      # https://github.com/Feuerlabs/exometer_core/pull/101
      # https://github.com/uwiger/setup/issues/44
      # {:setup, "~> 2.0", override: true},
      {:ex_doc, "~> 0.10", only: :dev}
      # {:mix_test_watch, "~> 0.5", only: [:dev, :test], runtime: false},
    ]
  end

  defp description() do
    "Reads Exometer metrics and generates a report in Prometheus text output format."
  end

  defp package() do
    [
      maintainers: ["Jake Morrison"],
      licenses: ["Mozilla Public License 2.0"],
      links: %{"GitHub" => "https://github.com/cogini/prometheus_exometer"}
    ]
  end
end
