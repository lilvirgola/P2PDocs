defmodule P2PDocs.MixProject do
  use Mix.Project

  def project do
    [
      app: :p2p_docs,
      version: "1.0.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "P2PDocs",
      docs: docs()
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
      # For the API server
      {:cowboy, "~> 2.9"},
      # For the API router
      {:plug, "~> 1.14"},
      # To connect Plug with Cowboy
      {:plug_cowboy, "~> 2.6"},
      # For JSON encoding/decoding
      {:jason, "~> 1.2"},
      # For documentation generation
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      # For dynamic creation of test mocks
      {:mox, "~> 0.5.2", only: :test}
    ]
  end

  # Run "mix help deps" to learn about ExDoc.
  defp docs do
    [
      main: "get_started",
      extras: ["get_started.md"],
      favicon: "assets/favicon.png",
      logo: "assets/logo.png",
      authors: ["Alessandro De Biasi", "Alessandro Minisini", "Nazareno Piccin"],
      nest_modules_by_prefix: [
        "P2PDocs",
        "P2PDocs.CRDT",
        "P2PDocs.Network",
        "P2PDocs.API",
        "P2PDocs.Utils"
      ],
      source_url_pattern:
        "https://github.com/lilvirgola/P2PDocs/blob/main/p2p_docs_backend/%{path}#L%{line}"
    ]
  end
end
