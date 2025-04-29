defmodule P2PDocs.MixProject do
  use Mix.Project

  def project do
    [
      app: :p2p_docs,
      version: "0.1.0",
      elixir: "~> 1.18",
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
      {:plug_cowboy, "~> 2.6"}, # for API server
      {:jason, "~> 1.4"}, # for JSON parsing
      {:ex_doc, "~> 0.30", only: :dev, runtime: false} # for documentation generation
    ]
  end
end
