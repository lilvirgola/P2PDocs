defmodule P2PDocs.CRDT.Manager do
  use GenServer
  require Logger

  alias P2PDocs.CRDT.CrdtText, as: CrdtText

   @table_name Application.compile_env(:p2p_docs, :crdt_manager)[:ets_table] ||
                      :crdt_manager_state

  defstruct peer_id: nil,
            crdt: nil

  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: __MODULE__)
  end

  @impl true
  def init(my_id) do
    try do
      case :ets.lookup(@table_name, my_id) do
        [{_key, state}] ->
          # State found in ETS, return it
          Logger.info("State found in ETS: #{inspect(state)}")
          # restore the state from ETS
          {:ok, state}


        [] ->
          Logger.info("No state found in ETS, creating new state")
          # No state found in ETS, create new state
          initial_state = %__MODULE__{
            peer_id: my_id,
            crdt: CrdtText.new(my_id)
          }
          # Store the initial state in the ETS table
          :ets.insert(@table_name, {my_id, initial_state})
          {:ok, initial_state}
      end
    catch
      :error, :badarg ->
        Logger.error("ETS table not found")
        {:stop, :badarg}
    end
  end

  def receive(msg) do
    GenServer.cast(__MODULE__, msg)
  end

  def get_state() do
    GenServer.call(__MODULE__, {:get_crdt})
    end

  def add_char(n) do
    total = n

    Enum.each(1..total,fn i ->
      # sorted = Enum.sort_by(st.chars, fn x -> {x.pos, x.id} end)
      # pick random adjacent pair
      idx = :rand.uniform(i)
      GenServer.cast(__MODULE__, {:local_insert, idx, "a" <> Integer.to_string(i)})
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
  def handle_call({:get_crdt}, _from, state) do
    Logger.debug("Node #{inspect(state.peer_id)} is sending its state!")
    {:reply, state.crdt, state}
  end

  @impl true
  def handle_cast({:upd_crdt, new_crdt}, state) do
    Logger.debug("Node #{inspect(state.peer_id)} is updating its state!")
    new_state = %__MODULE__{
      state
      | crdt: new_crdt
    }
    # Store the updated state in ETS
    :ets.insert(@table_name, {state.peer_id, new_state})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remote_insert, char}, state) do
    Logger.debug(
      "Node #{inspect(state.peer_id)} is applying the remote insert of #{inspect(char)}!"
    )
    {_, new_crdt} = CrdtText.apply_remote_insert(state.crdt, char)
    new_state = %__MODULE__{
      state
      | crdt: new_crdt
    }
    # Store the updated state in ETS
    :ets.insert(@table_name, {state.peer_id, new_state})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remote_delete, target_id}, state) do
    Logger.debug(
      "Node #{inspect(state.peer_id)} is applying the remote delete of #{inspect(target_id)}!"
    )

    {_, new_crdt} = CrdtText.apply_remote_delete(state.crdt, target_id)

    new_state = %__MODULE__{
      state
      | crdt: new_crdt
    }
    # Store the updated state in ETS
    :ets.insert(@table_name, {state.peer_id, new_state})
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
    # Store the updated state in ETS
    :ets.insert(@table_name, {state.peer_id, new_state})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:local_delete, index}, state) do
    Logger.debug("Node #{inspect(state.peer_id)} is applying the local delete!")

    {target_id, new_crdt} = CrdtText.delete_local(state.crdt, index)

    new_state = %__MODULE__{
      state
      | crdt: new_crdt
    }

    P2PDocs.Network.CausalBroadcast.broadcast({:remote_delete, target_id})
    # Store the updated state in ETS
    :ets.insert(@table_name, {state.peer_id, new_state})
    {:noreply, new_state}
  end

  def handle_cast(_, state) do
    Logger.error("Message not valid!")
    {:noreply, state}
  end
end
