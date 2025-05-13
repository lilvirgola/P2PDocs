defmodule P2PDocs.Utils.Graphviz do
  def to_dot(topology, opts \\ []) do
    directed = Keyword.get(opts, :directed, false)

    header = if directed, do: "digraph G {", else: "graph G {"
    connector = if directed, do: " -> ", else: " -- "

    edges =
      Enum.flat_map(topology, fn {node, neighbors} ->
        Enum.map(neighbors, fn neighbor ->
          ordered = Enum.sort([node, neighbor])
          {Enum.at(ordered, 0), Enum.at(ordered, 1)}
        end)
      end)
      |> Enum.uniq()

    body =
      Enum.map(edges, fn {a, b} ->
        "  #{a}#{connector}#{b};"
      end)

    Enum.join([header | body] ++ ["}"], "\n")
  end

  def save_dot_file(topology, file_name, opts \\ []) do
    dot = to_dot(topology, opts)
    File.write!(file_name, dot)
  end
end
