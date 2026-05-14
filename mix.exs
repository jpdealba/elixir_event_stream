defmodule AlertMedia.MixProject do
  use Mix.Project

  def project do
    [
      app: :alert_media,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AlertMedia.Application, []}
    ]
  end

  defp deps do
    [
      {:broadway, "~> 1.1"},
      {:broadway_sqs, "~> 0.7"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_sqs, "~> 3.4"},
      {:hackney, "~> 1.20"},
      {:jason, "~> 1.4"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"}
    ]
  end
end
