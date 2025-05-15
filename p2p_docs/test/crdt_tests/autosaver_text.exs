defmodule AutoSaverTest do
  use ExUnit.Case, async: true

  alias P2PDocs.CRDT.AutoSaver
  alias P2PDocs.CRDT.CrdtText

  setup do
    # Create a unique temp file path for each test
    path =
      "/tmp/autosaver_test_#{:erlang.unique_integer([:positive])}.txt"

    # Ensure the file is removed after the test
     on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  describe "auto-saving on insert" do
    test "does not save before threshold and saves after threshold inserts", %{path: path} do
      crdt = CrdtText.new("peer")
      auto = AutoSaver.new(crdt, 2, path)

      {_, auto} = AutoSaver.local_insert(auto, 1, "a")
      refute File.exists?(path)

      {_, auto} = AutoSaver.local_insert(auto, 2, "b")
      assert File.exists?(path)
      assert File.read!(path) == "ab"
    end
  end

  describe "auto-saving on delete" do
    test "saves empty text after deleting the only character", %{path: path} do
      # Start with one character in CRDT
      crdt0 = CrdtText.new("peer")
      {_msg, crdt1} = CrdtText.insert_local(crdt0, 1, "x")
      auto = AutoSaver.new(crdt1, 1, path)
      # Delete at index 1 (between begin and end markers)
      {_, auto} = AutoSaver.local_delete(auto, 1)

      assert File.exists?(path)
      assert File.read!(path) == ""
    end
  end

  describe "resetting change count and overwriting file" do
    test "overwrites previous save after subsequent threshold cycles", %{path: path} do
      crdt = CrdtText.new("peer")
      auto = AutoSaver.new(crdt, 2, path)

      # First cycle
      {_, auto} = AutoSaver.local_insert(auto, 1, "c")
      {_, auto} = AutoSaver.local_insert(auto, 2, "d")
      assert File.read!(path) == "cd"

      # Second cycle
      {_, auto} = AutoSaver.local_insert(auto, 3, "e")
      refute File.read!(path) == "cde"

      {_, auto} = AutoSaver.local_insert(auto, 4, "f")
      assert File.read!(path) == "cdef"
    end
  end
end
