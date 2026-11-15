defmodule Rock.MixProject do
  use Mix.Project

  def project do
    [
      app: :rock,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :crypto],
      mod: {Rock.Application, []}
    ]
  end

  defp deps do
    []
  end

  defp aliases do
    [
      precommit: ["compile --warnings-as-errors", "test"]
    ]
  end
end
