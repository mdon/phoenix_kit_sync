defmodule PhoenixKitSync.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Peer-to-peer data sync module for PhoenixKit"
  @source_url "https://github.com/BeamLabEU/phoenix_kit_sync"

  def project do
    [
      app: :phoenix_kit_sync,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:phoenix_kit]],
      package: package(),
      docs: docs(),
      name: "PhoenixKitSync",
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": ["format --check-formatted", "credo --strict", "dialyzer"],
      precommit: ["compile", "quality"],
      "test.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "test.reset": ["ecto.drop --quiet", "test.setup"]
    ]
  end

  defp package do
    [
      name: "phoenix_kit_sync",
      maintainers: ["BeamLab EU"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib docs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      name: "PhoenixKitSync",
      source_ref: "v#{@version}",
      source_url: @source_url,
      main: "readme",
      extras: ["README.md"]
    ]
  end

  defp deps do
    [
      {:phoenix_kit, "~> 1.7"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix, "~> 1.8.1"},
      {:ecto_sql, "~> 3.10"},
      {:websockex, "~> 0.5.1"},
      {:websock_adapter, "~> 0.5"},
      {:oban, "~> 2.20"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
