defmodule P2PDocs.CRDT.Manager do
  use GenServer
  require Logger

  alias P2PDocs.CRDT.CrdtText, as: CrdtText

  defstruct peer_id: nil,
            crdt: nil

  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: __MODULE__)
  end

  @impl true
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

  def add_char(n) do
    total = n

    Enum.reduce(1..total, 0, fn i, st ->
      # sorted = Enum.sort_by(st.chars, fn x -> {x.pos, x.id} end)
      # pick random adjacent pair
      idx = :rand.uniform(i)
      GenServer.cast(__MODULE__, {:local_insert, idx, "a" <> Integer.to_string(i)})
      st
    end)
  end

  def print_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    ans = CrdtText.to_plain_text(state.crdt)
    {:reply, ans, state}
  end

  @impl true
  def handle_cast({:get_crdt}, state) do
    Logger.debug("Node #{inspect(state.peer_id)} is sending its state!")
    {:reply, state.crdt, state}
  end

  @impl true
  def handle_cast({:remote_insert, char}, state) do
    Logger.debug(
      "Node #{inspect(state.peer_id)} is applying the remote insert of #{inspect(char)}!"
    )

    new_state = %__MODULE__{
      state
      | crdt: CrdtText.apply_remote_insert(state.crdt, char)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remote_delete, target_id}, state) do
    Logger.debug(
      "Node #{inspect(state.peer_id)} is applying the remote delete of #{inspect(target_id)}!"
    )

    new_state = %__MODULE__{
      state
      | crdt: CrdtText.apply_remote_delete(state.crdt, target_id)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:local_insert, index, value}, state) do
    Logger.debug("Node #{inspect(state.peer_id)} is applying the local insert at #{index}!")

    {new_char, new_crdt} = CrdtText.insert_local(state.crdt, index, value)

    new_state = %__MODULE__{
      state
      | crdt: new_crdt
    }

    P2PDocs.Network.CausalBroadcast.broadcast({:remote_insert, new_char})

    {:noreply, new_state}
  end

  @impl true
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

  def handle_cast(_, state) do
    Logger.error("Message not valid!")
    {:noreply, state}
  end
end
