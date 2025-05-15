defmodule EchoWaveTest do
  use ExUnit.Case
  alias P2PDocs.Network.EchoWave
  alias P2PDocs.Utils

  @moduletag :capture_log

  test "echo wave static topology" do
    topology = %{
      :a => [:b, :c],
      :b => [:a, :d, :e],
      :c => [:a, :e],
      :d => [:b, :e],
      :e => [:b, :c, :d]
    }

    Utils.Graphviz.save_dot_file(topology, "static_topology.dot")

    root = :a
    start_echo_wave(topology, root)
  end

  test "echo wave random connected graph" do
    size = 2 ** 4
    gamma = 1.2
    {time, topology} = :timer.tc(fn -> build_random_topology(size, gamma) end)

    IO.puts("Random graph creation with #{size} nodes: #{time} microseconds")

    Utils.Graphviz.save_dot_file(topology, "random_topology.dot")

    root = Map.keys(topology) |> Enum.random()

    start_echo_wave(topology, root)
  end

  defp start_echo_wave(topology, root) do
    size = Map.keys(topology) |> Enum.count()

    for {id, neighbors} <- topology do
      EchoWave.start_link({id, neighbors}, id)
    end

    GenServer.cast(EchoWave.get_peer(root), {:token, self(), 0, nil})

    {time, value} =
      :timer.tc(fn -> assert_receive {:tree_complete, ^root, ^size, _}, 10 * size end)

    IO.puts("Echo Wave on #{size} nodes: #{time} microseconds")
    value
  end

  defp build_random_topology(size, gamma) do
    nodes = Enum.map(1..size, fn i -> String.to_atom("n#{i}") end)

    # Build a spanning tree
    shuffled = Enum.shuffle(nodes)

    tree_edges =
      Enum.chunk_every(shuffled, 2, 1, :discard)
      |> Enum.map(fn [a, b] -> {a, b} end)

    # Add some random extra edges
    extra_edges =
      for a <- nodes, b <- nodes, a < b, :rand.uniform() < 1 / size ** gamma, do: {a, b}

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
end
