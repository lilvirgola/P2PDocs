# lib/crdt/manager.ex
defmodule CRDT.Manager do
  @moduledoc """
  Keeps one CRDT per peer_id in ETS, applies incoming ops,
  and broadcasts them via pg2.
  """

  use GenServer

  @table :crdt_table
  @group :crdt_group

  # Public API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Apply a single CRDT op for peer_id"
  def apply_op(peer_id, op) do
    GenServer.cast(__MODULE__, {:apply_op, peer_id, op})
  end

  @doc "Get the full document string for peer_id"
  def get_doc(peer_id) do
    GenServer.call(__MODULE__, {:get_doc, peer_id})
  end

  ## GenServer callbacks

  @impl true
  def init(_) do
    # ensure ETS table
    :ets.new(@table, [:named_table, :public, :set, {:read_concurrency, true}])
    # ensure pg2 group for broadcasting
    :pg2.create(@group)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_doc, peer_id}, _from, state) do
    crdt =
      case :ets.lookup(@table, peer_id) do
        [{^peer_id, existing}] -> existing
        [] ->
          new = CrdtLib.new()
          :ets.insert(@table, {peer_id, new})
          new
      end

    {:reply, CrdtLib.to_string(crdt), state}
  end

  @impl true
  def handle_cast({:apply_op, peer_id, op_map}, state) do
    old_crdt =
      case :ets.lookup(@table, peer_id) do
        [{^peer_id, existing}] -> existing
        [] -> CrdtLib.new()
      end

    new_crdt = CrdtLib.apply(op_map, old_crdt)
    :ets.insert(@table, {peer_id, new_crdt})

    # broadcast to all websocket handlers
    broadcast(peer_id, op_map)

    {:noreply, state}
  end

  # helper to broadcast via pg2
  defp broadcast(peer_id, op) do
    payload = {:broadcast, peer_id, op}
    # get_members can fail if group not created,
    # but we created it in init/1
    for pid <- :pg2.get_members(@group) do
      send(pid, payload)
    end
  end
end
