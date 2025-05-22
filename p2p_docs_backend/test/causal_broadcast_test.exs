defmodule P2PDocs.Network.CausalBroadcastTest do
  use ExUnit.Case, async: false
  import Mox

  alias P2PDocs.Network.CausalBroadcast
  alias P2PDocs.Network.NaiveVectorClock

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # reset ETS table so each test starts clean
    table =
      Application.get_env(:p2p_docs, :causal_broadcast)[:ets_table] ||
        :causal_broadcast_state

    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    :ets.new(table, [:named_table, :public, :set])

    :ok
  end

  describe "broadcast/1" do
    test "increments its vector clock and calls echo_wave with the new VC and message" do
      # Expect the echo_wave mock to be invoked once with the incremented VC and the right tuple
      P2PDocs.Network.EchoWaveMock
      |> expect(:start_echo_wave, fn new_vc, {:message, payload, sender_id, new_vc_1} ->
        assert payload == "hello"
        assert sender_id == :node1
        assert new_vc == new_vc_1
        :ok
      end)

      # Start the server under test
      {:ok, _pid} =
        CausalBroadcast.start_link(
          my_id: :node1,
          nodes: [:node1],
          delivery_pid: self()
        )

      # Fire off a broadcast
      assert :ok == CausalBroadcast.broadcast("hello")

      # Give the cast a moment to run
      Process.sleep(10)

      # Verify that the in‐memory state was updated
      %{t: vc} = CausalBroadcast.get_state()
      assert vc == %{node1: 1}

      # And that ETS was updated, too
      [{_, saved_state}] =
        :ets.lookup(:causal_broadcast_state, :node1)

      assert saved_state.t == vc
    end
  end

  describe "deliver_to_causal/2" do
    test "when causal conditions are met, it calls crdt_manager.receive/1 and updates d" do
      # Build a vector‐clock with count 1 for :node1
      vc =
        NaiveVectorClock.new(:node1)
        |> NaiveVectorClock.increment(:node1)

      msg = {:message, "world", :node1, vc}

      # Expect the CRDT‐manager mock to receive exactly the bare payload
      P2PDocs.CRDT.ManagerMock
      |> expect(:receive_msg, fn delivered_payload ->
        assert delivered_payload == "world"
        :ok
      end)

      # Start the server with two nodes, so we can accept a message from :node1
      {:ok, _pid} =
        CausalBroadcast.start_link(
          my_id: :node2,
          nodes: [:node1, :node2],
          delivery_pid: self()
        )

      # Inject the message
      assert :ok == CausalBroadcast.deliver_to_causal(msg)

      # Wait for the cast & delivery
      Process.sleep(10)

      # Now check that the delivery counter for :node1 was bumped to 1
      {_, d_state} = CausalBroadcast.get_vc_and_d_state()
      assert d_state[:node1] == 1
    end

    test "when higher vc is recived it doesn't deliver the message" do
      vc_lower =
        NaiveVectorClock.new(:node1)
        |> NaiveVectorClock.increment(:node1)

      msg_lower = {:message, "world", :node1, vc_lower}
      vc_higher = NaiveVectorClock.increment(vc_lower, :node1)
      msg_higher = {:message, "hello", :node1, vc_higher}
      # Expect the CRDT‐manager mock to receive exactly the bare payload
      P2PDocs.CRDT.ManagerMock
      |> expect(:receive_msg, 2, fn delivered_payload ->
        assert delivered_payload in ["hello", "world"]
        :ok
      end)

      # Start the server with two nodes, so we can accept a message from :node1
      {:ok, _pid} =
        CausalBroadcast.start_link(
          my_id: :node2,
          nodes: [:node1, :node2],
          delivery_pid: self()
        )

      # Inject the higher message
      assert :ok == CausalBroadcast.deliver_to_causal(msg_higher)
      # Wait for the cast & delivery
      Process.sleep(10)
      state1 = CausalBroadcast.get_state()
      assert MapSet.size(state1.buffer) == 1
      assert :ok == CausalBroadcast.deliver_to_causal(msg_lower)
      # Wait for the cast & delivery
      Process.sleep(10)
      state2 = CausalBroadcast.get_state()
      assert MapSet.size(state2.buffer) == 0
    end

    test "concurrent messages are immediatly delivered" do
      vc_1 =
        NaiveVectorClock.new(:node1)
        |> NaiveVectorClock.increment(:node1)

      msg_1 = {:message, "world", :node1, vc_1}

      vc_2 =
        NaiveVectorClock.new(:node2)
        |> NaiveVectorClock.increment(:node2)

      msg_2 = {:message, "hello", :node2, vc_2}
      # Expect the CRDT‐manager mock to receive exactly the bare payload
      P2PDocs.CRDT.ManagerMock
      |> expect(:receive_msg, 2, fn delivered_payload ->
        assert delivered_payload in ["hello", "world"]
        :ok
      end)

      # Start the server with two nodes, so we can accept a message from :node1
      {:ok, _pid} =
        CausalBroadcast.start_link(
          my_id: :node3,
          nodes: [:node1, :node2, :node3],
          delivery_pid: self()
        )

      # Inject the higher message
      assert :ok == CausalBroadcast.deliver_to_causal(msg_1)
      # Wait for the cast & delivery
      Process.sleep(10)
      state1 = CausalBroadcast.get_state()
      assert MapSet.size(state1.buffer) == 0
      assert :ok == CausalBroadcast.deliver_to_causal(msg_2)
      # Wait for the cast & delivery
      Process.sleep(10)
      state2 = CausalBroadcast.get_state()
      assert MapSet.size(state2.buffer) == 0
    end
  end
end
