defmodule DailyDumb.MixProject do
  use Mix.Project

  def project do
    [
      app: :daily_report,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ranch, :plug_cowboy, :mnesia, :inets],
      mod: {DailyReport.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:myxql, "~> 0.6.2"},
      {:csv, "~> 2.4"},
      {:plug_cowboy, "~> 2.0"},
      {:poison, "~> 3.1"}
    ]
  end
end
