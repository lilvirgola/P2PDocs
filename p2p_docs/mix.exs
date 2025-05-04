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
        main: "P2PDocs",
        extras: ["README.md"],
        formatters: ["html", "epub"]
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
      {:plug_cowboy, "~> 2.6"},
      # for JSON parsing
      {:jason, "~> 1.4"},
      # Socket acceptor pool
      {:ranch, "~> 2.0"},
      # Raw UDP socket support
      {:socket, "~> 0.3"},
      # for documentation generation
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end
end
