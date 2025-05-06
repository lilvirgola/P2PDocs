defmodule EchoWaveTest do
  use ExUnit.Case
  alias EchoWave.EchoNode

  # Non so perchè ma qua `setup` non funziona, in un test in locale sì
  # setup do
  #   Registry.start_link(keys: :unique, name: :echo_registry)
  #   :ok
  # end

  defp build_random_topology(size) do
    nodes = Enum.map(1..size, fn i -> String.to_atom("n#{i}") end)

    # Build a spanning tree
    shuffled = Enum.shuffle(nodes)

    tree_edges =
      Enum.chunk_every(shuffled, 2, 1, :discard)
      |> Enum.map(fn [a, b] -> {a, b} end)

    # Add some random extra edges
    extra_edges = for a <- nodes, b <- nodes, a < b, :rand.uniform() < 0.2, do: {a, b}
    edges = Enum.uniq(tree_edges ++ extra_edges)

    Map.new(nodes, fn n ->
      neighbors =
        Enum.flat_map(edges, fn
          {^n, other} -> [other]
          {other, ^n} -> [other]
          _ -> []
        end)

      {n, neighbors}
    end)
  end

  defp start_echo_wave(topology, root) do
    for {id, neighbors} <- topology do
      EchoNode.start_link({id, neighbors})
    end

    GenServer.cast(EchoNode.via_tuple(root), {:token, self(), 0})
  end

  test "echo wave static topology" do
    topology = %{
      :a => [:b, :c],
      :b => [:a, :d, :e],
      :c => [:a, :e],
      :d => [:b, :e],
      :e => [:b, :c, :d]
    }

    EchoWave.Graphviz.save_dot_file(topology, "static_topology.dot")

    root = :a
    size = Map.keys(topology) |> Enum.count()
    start_echo_wave(topology, root)
    assert_receive {:tree_complete, ^root, ^size}, 1_000
  end

  test "echo wave random connected graph" do
    topology = build_random_topology(16)

    EchoWave.Graphviz.save_dot_file(topology, "random_topology.dot")

    root = Map.keys(topology) |> Enum.random()
    size = Map.keys(topology) |> Enum.count()
    start_echo_wave(topology, root)
    assert_receive {:tree_complete, ^root, ^size}, 2_000
  end
end
