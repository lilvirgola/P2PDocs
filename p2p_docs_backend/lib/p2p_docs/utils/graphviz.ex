defmodule P2PDocs.Utils.Graphviz do
  @moduledoc """
  This module provides functions to convert a topology represented as a map
  into a Graphviz DOT format string. It also includes a function to save the
  generated DOT string to a file.
  """
  def to_dot(topology, opts \\ []) do
    directed = Keyword.get(opts, :directed, false)

    header = if directed, do: "digraph G {", else: "graph G {"
    connector = if directed, do: " -> ", else: " -- "

    attrs = Keyword.get(opts, :attrs, layout: "sfdp", beautify: "true", overlap: "scale")

    attr_list =
      attrs
      |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
      |> Enum.join(", ")

    graph_attr_line = "  graph [#{attr_list}];"

    edges =
      topology
      |> Enum.flat_map(fn {node, neighbors} ->
        for m <- neighbors, do: Enum.sort([node, m]) |> List.to_tuple()
      end)
      |> Enum.uniq()

    body =
      for {a, b} <- edges do
        "  #{a}#{connector}#{b};"
      end

    [
      header,
      graph_attr_line
      | body
    ]
    |> Enum.concat(["}"])
    |> Enum.join("\n")
  end

  def save_dot_file(topology, file_name, opts \\ []) do
    dot = to_dot(topology, opts)
    File.write!(file_name, dot)
  end
end
