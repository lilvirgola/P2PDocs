defmodule CRDT.Manager do
  use GenServer
  require Logger

  defstruct peer_id: nil,
            crdt: nil

  @impl true
  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id)
  end

  def init(id) do
    state = %__MODULE__{
      peer_id: id,
      crdt: CrdtText.new(id)
    }

    {:ok, state}
  end

  def receive(msg) do
    GenServer.cast(__MODULE__, msg)
  end

  def add_char(cnt) do
    idx = :rand.uniform(cnt + 1)
    GenServer.cast(__MODULE__, {:local_insert, idx, Integer.to_string(idx)})
  end

  def handle_cast({:remote_insert, char}, state) do
    Logger.debug("Node #{state.peer_id} is applying the remote insert of #{char}!")

    new_state = %__MODULE__{
      state
      | crdt: CrdtText.apply_remote_insert(state.crdt, char)
    }

    {:noreply, new_state}
  end

  def handle_cast({:remote_delete, target_id}, state) do
    Logger.debug("Node #{state.id} is applying the remote delete of #{target_id}!")

    new_state = %__MODULE__{
      state
      | crdt: CrdtText.apply_remote_delete(state.crdt, target_id)
    }

    {:noreply, new_state}
  end

  def handle_cast({:local_insert, index, value}, state) do
    Logger.debug("Node #{state.peer_id} is applying the local insert!")

    {new_char, new_crdt} = CrdtText.insert_local(state.crdt, index, value)

    new_state = %__MODULE__{
      state
      | crdt: new_crdt
    }

    P2PDocs.Network.CausalBroadcast.broadcast({:remote_insert, new_char})

    {:noreply, new_state}
  end

  def handle_cast({:local_delete, index}, state) do
    Logger.debug("Node #{state.id} is applying the local delete!")

    {target_id, new_crdt} = CrdtText.delete_local(state.crdt, index)

    new_state = %__MODULE__{
      state
      | crdt: new_crdt
    }

    P2PDocs.Network.CausalBroadcast.broadcast({:remote_delete, target_id})

    {:noreply, new_state}
  end
end
