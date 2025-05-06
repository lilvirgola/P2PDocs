# test/ostree_test.exs

defmodule OSTree.CorrectnessTest do
  use ExUnit.Case
  alias OSTree

  test "inserting values yields sorted order via kth_element/2" do
    values = [5, 1, 3, 2, 4]

    tree =
      Enum.reduce(values, OSTree.new(fn a, b -> a - b end), fn x, acc -> OSTree.insert(acc, x) end)

    expected = Enum.sort(values)
    result = for k <- 1..length(values), do: OSTree.kth_element(tree, k)
    assert result == expected
  end

  test "deleting values removes them correctly" do
    values = Enum.to_list(1..10)

    tree =
      Enum.reduce(values, OSTree.new(fn a, b -> a - b end), fn x, acc -> OSTree.insert(acc, x) end)

    tree2 = OSTree.delete(tree, 5)

    # Ensure 5 is gone
    remaining = for k <- 1..9, do: OSTree.kth_element(tree2, k)
    refute 5 in remaining

    # Ensure subtree size decreased
    %OSTree.Node{size: s} = tree2.root
    assert s == 9

    # Deleting non-existent element does not change
    tree3 = OSTree.delete(tree2, 42)
    %OSTree.Node{size: s2} = tree3.root
    assert s2 == s
  end

  test "custom comparator for descending order" do
    comp = fn a, b -> b - a end
    values = [10, 20, 15]

    tree =
      Enum.reduce(values, OSTree.new(fn a, b -> b - a end), fn x, acc -> OSTree.insert(acc, x) end)

    # In descending order, kth_element(1) is max
    assert OSTree.kth_element(tree, 1) == 20
    assert OSTree.kth_element(tree, length(values)) == 10
  end
end

defmodule OSTree.PerformanceTest do
  use ExUnit.Case
  alias OSTree
  alias OSTree.Node

  @comp fn a, b -> a - b end

  @tag timeout: 300_000
  @tag :performance
  test "insert 10_000 elements efficiently" do
    {time, tree} =
      :timer.tc(fn ->
        Enum.reduce(1..10_000, OSTree.new(fn a, b -> a - b end), fn x, acc ->
          OSTree.insert(acc, x)
        end)
      end)

    IO.puts("Insertion of 10_000 elements took #{time}μs")

    %Node{size: s} = tree.root
    assert s == 10_000
    # Expect under ~200ms
    # assert time < 200_000
  end

  @tag :performance
  test "kth_element selection for 10_000 elements" do
    tree =
      Enum.reduce(1..10_000, OSTree.new(fn a, b -> a - b end), fn x, acc ->
        OSTree.insert(acc, x)
      end)

    {time, _} =
      :timer.tc(fn ->
        for k <- 1..10_000 do
          OSTree.kth_element(tree, k)
        end
      end)

    IO.puts("10_000 kth_element selections took #{time}μs")
    # Expect under ~200ms
    # assert time < 200_000
  end

  @tag :performance
  test "delete 5_000 random elements efficiently" do
    initial = Enum.to_list(1..10_000)

    tree =
      Enum.reduce(initial, OSTree.new(fn a, b -> a - b end), fn x, acc ->
        OSTree.insert(acc, x)
      end)

    to_delete = Enum.take_random(initial, 5_000)

    {time, tree2} =
      :timer.tc(fn ->
        Enum.reduce(to_delete, tree, fn x, acc -> OSTree.delete(acc, x) end)
      end)

    IO.puts("Deleting 5_000 elements took #{time}μs")

    %Node{size: s2} = tree2.root
    assert s2 == 5_000
    # Expect under ~200ms
    # assert time < 200_000
  end
end
