defmodule P2PDocs.Network.CausalBroadcastTest do
  use ExUnit.Case, async: false

  alias P2PDocs.Network.CausalBroadcast

  setup do
    # Pulizia ETS prima di ogni test
    :ets.delete_all_objects(:causal_broadcast_state)

    {:ok, _pid} =
      start_supervised!(
        {CausalBroadcast, my_id: :node1, nodes: [:node1, :node2], delivery_pid: self()}
      )

    :ok
  end

  test "start_link initializes state correctly" do
    state = CausalBroadcast.get_state()
    assert state.my_id == :node1
    assert Enum.sort(state.nodes) == [:node1, :node2]
  end

  test "add_node/1 adds a new node" do
    :ok = CausalBroadcast.add_node(:node3)
    state = CausalBroadcast.get_state()
    assert :node3 in state.nodes
  end

  test "remove_node/1 removes a node" do
    :ok = CausalBroadcast.remove_node(:node2)
    state = CausalBroadcast.get_state()
    refute :node2 in state.nodes
  end

  test "broadcast sends message and updates vector clock" do
    CausalBroadcast.broadcast("Hello world")

    # Di norma qui aspetteremmo un messaggio da un altro nodo, ma per ora testiamo solo che il VC sia aggiornato
    state = CausalBroadcast.get_state()
    assert Map.get(state.t, :node1) == 1
  end

  test "delivers message if causal dependencies met" do
    # Simuliamo un messaggio ricevuto da un altro nodo
    vector_clock = %{node1: 0, node2: 1}
    send(CausalBroadcast, {:message, "from node2", :node2, vector_clock})

    # Attendi che il messaggio venga processato
    Process.sleep(100)

    state = CausalBroadcast.get_state()
    assert {"from node2", :node2, vector_clock} in state.delivery_log
  end
end
