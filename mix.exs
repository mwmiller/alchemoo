defmodule Alchemoo.MixProject do
  use Mix.Project

  def project do
    [
      app: :alchemoo,
      version: "0.3.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "A modern LambdaMOO-compatible server built on the BEAM",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Alchemoo.Application, []}
    ]
  end

  defp deps do
    [
      {:nimble_parsec, "~> 1.4"},
      {:ranch, "~> 2.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
      # Optional: For SSH fingerprint visualization (drunken bishop)
      # {:fingerart, "~> 1.0", optional: true}  # CONFIG: Uncomment when SSH is implemented
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp aliases do
    [
      precommit: [
        "compile --force --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test"
      ]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/yourusername/alchemoo"}
    ]
  end
end
