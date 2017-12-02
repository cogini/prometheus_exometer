defmodule PrometheusExometer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :prometheus_exometer,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:exometer_core, github: "Feuerlabs/exometer_core", tag: "1.5.0"},
      {:setup, github: "uwiger/setup", manager: :rebar, override: true} # fix for https://github.com/uwiger/setup/issues/24
    ]
  end
end
