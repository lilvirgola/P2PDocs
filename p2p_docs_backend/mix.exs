defmodule P2PDocs.MixProject do
  use Mix.Project

  def project do
    [
      app: :p2p_docs,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "P2PDocs",
      docs: [
        main: "P2PDocs.Application",
        extras: ["README.md"],
        formatters: ["html", "epub"],
        favicon: "assets/favicon.png",
        logo: "assets/logo.png"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {P2PDocs.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # for API server
      {:cowboy, "~> 2.9"},
      # For the router
      {:plug, "~> 1.14"},
      # To connect Plug with Cowboy
      {:plug_cowboy, "~> 2.6"},
      {:jason, "~> 1.2"},
      # for documentation generation
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      # for the dynamic creation of test mocks
      {:mox, "~> 0.5.2", only: :test}
    ]
  end
end
