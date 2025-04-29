defmodule P2pDocsTest do
  use ExUnit.Case
  doctest P2pDocs

  test "greets the world" do
    assert P2pDocs.hello() == :world
  end
end
