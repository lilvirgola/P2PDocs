defmodule P2PDocs.CRDT.CrdtTextTest do
  use ExUnit.Case
  alias P2PDocs.CRDT.CrdtText
  alias P2PDocs.CRDT.OSTree

  setup do
    # Seed randomness for reproducible position allocation
    :rand.seed(:exsplus, {123, 456, 789})
    :ok
  end

  describe "new/1" do
    test "initializes with empty tree and correct peer_id" do
      state = CrdtText.new("peer1")
      assert state.peer_id == "peer1"
      # to_plain_text on empty should be []
      assert CrdtText.to_plain_text(state) == []
    end
  end

  describe "insert_local/3 and to_plain_text/1" do
    test "inserts characters at correct indices" do
      state = CrdtText.new("p")

      {char_a, state} = CrdtText.insert_local(state, 1, "A")
      assert char_a.value == "A"
      assert CrdtText.to_plain_text(state) == ["A"]

      {char_b, state} = CrdtText.insert_local(state, 2, "B")
      assert char_b.value == "B"
      assert CrdtText.to_plain_text(state) == ["A", "B"]

      {char_c, state} = CrdtText.insert_local(state, 2, "C")
      assert char_c.value == "C"
      assert CrdtText.to_plain_text(state) == ["A", "C", "B"]
    end
  end

  describe "delete_local/2" do
    test "deletes character by index" do
      state = CrdtText.new("p")
      {_a, state} = CrdtText.insert_local(state, 1, "X")
      {_b, state} = CrdtText.insert_local(state, 2, "Y")
      assert CrdtText.to_plain_text(state) == ["X", "Y"]

      {_id_del, state} = CrdtText.delete_local(state, 1)
      # Ensure id_deleted matches removed char
      assert CrdtText.to_plain_text(state) == ["Y"]
    end
  end

  describe "apply_remote_insert/2" do
    test "inserts remote char when new and returns index" do
      # Create two states
      local = CrdtText.new("p1")
      {char, _local} = CrdtText.insert_local(local, 1, "Z")

      remote = CrdtText.new("p2")
      {index, state2} = CrdtText.apply_remote_insert(remote, char)

      assert index == 1
      assert CrdtText.to_plain_text(state2) == ["Z"]

      # Applying same again returns nil and no change
      {index2, state3} = CrdtText.apply_remote_insert(state2, char)
      assert index2 == nil
      assert CrdtText.to_plain_text(state3) == ["Z"]
    end
  end

  describe "apply_remote_delete/2" do
    test "deletes existing char by id and returns index" do
      state = CrdtText.new("p")
      {char, state} = CrdtText.insert_local(state, 1, "Q")

      {index, state} = CrdtText.apply_remote_delete(state, char.id)
      assert index == 1
      assert CrdtText.to_plain_text(state) == []

      # Deleting non-existent id returns nil and state unchanged
      {index2, state2} = CrdtText.apply_remote_delete(state, {"other", 1})
      assert index2 == nil
      assert state2 == state
    end
  end
end

defmodule P2PDocs.CRDT.CrdtTextPerformanceTest do
  use ExUnit.Case
  alias P2PDocs.CRDT.CrdtText
  alias P2PDocs.CRDT.OSTree

  @total_elements 100_000
  @tag timeout: 300_000
  @tag :performance
  test "random local inserts to test performances" do
    state = CrdtText.new("peer1")

    {time, final_state} =
      :timer.tc(fn ->
        Enum.reduce(1..@total_elements, state, fn i, st ->
          idx = :rand.uniform(OSTree.get_size(st.chars) + 1)
          {_, new_st} = CrdtText.insert_local(st, idx, Integer.to_string(i))
          new_st
        end)
      end)

    IO.puts("CrdtTextTest: inserting #{@total_elements} elements took #{time}μs")
    assert OSTree.get_size(final_state.chars) == @total_elements
  end
end
