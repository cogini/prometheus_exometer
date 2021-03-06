defmodule PrometheusExometer.MixProject do
  use Mix.Project

  @github "https://github.com/cogini/prometheus_exometer"

  def project do
    [
      app: :prometheus_exometer,
      version: "0.2.0",
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      source_url: @github,
      homepage_url: @github,
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:mix, :eex]
        # plt_add_deps: true,
        # flags: ["-Werror_handling", "-Wrace_conditions"],
        # flags: ["-Wunmatched_returns", :error_handling, :race_conditions, :underspecs],
        # ignore_warnings: "dialyzer.ignore-warnings"
      ],
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # extra_applications: [:logger] ++ extra_applications(Mix.env())
      # extra_applications: [:logger]
    ]
  end

  # defp extra_applications(:test), do: []
  # defp extra_applications(_),     do: []

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false},
      # {:exometer_core, github: "Feuerlabs/exometer_core", tag: "1.5.0"},
      {:exometer_core, "~> 1.5"},
      # {:setup, github: "uwiger/setup", manager: :rebar, override: true}, # fix for https://github.com/uwiger/setup/issues/24
      # https://github.com/Feuerlabs/exometer_core/pull/101
      # https://github.com/uwiger/setup/issues/44
      # {:setup, "~> 2.0", override: true},
      {:ex_doc, "~> 0.19.2", only: :dev, runtime: false},
      {:excoveralls, "~> 0.12.0", only: [:dev, :test], runtime: false}
      # {:mix_test_watch, "~> 0.5", only: [:dev, :test], runtime: false},
    ]
  end

  defp description do
    "Read Exometer metrics and generate Prometheus text output."
  end

  defp package do
    [
      maintainers: ["Jake Morrison"],
      licenses: ["Mozilla Public License 2.0"],
      links: %{"GitHub" => @github}
    ]
  end

  defp docs do
    [
      source_url: @github,
      extras: ["README.md", "CHANGELOG.md"],
      # api_reference: false,
      source_url_pattern: "#{@github}/blob/master/%{path}#L%{line}"
    ]
  end
end
