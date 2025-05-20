defmodule P2PDocs.CRDT.Manager do
  use GenServer
  require Logger

  alias P2PDocs.Network.CausalBroadcast
  alias P2PDocs.CRDT.CrdtText
  alias P2PDocs.CRDT.AutoSaver
  alias P2PDocs.API.WebSocket.Handler

  @table_name Application.compile_env(:p2p_docs, :crdt_manager)[:ets_table] ||
                :crdt_manager_state

  defstruct peer_id: nil,
            crdt: nil,
            auto_saver: nil

  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: __MODULE__)
  end

  @impl true
  def init(peer_id) do
    Logger.debug("Starting CRDT Manager module for node #{inspect(peer_id)}")
    Process.flag(:trap_exit, true)

    try do
      case :ets.lookup(@table_name, peer_id) do
        [{_key, state}] ->
          # State found in ETS, return it
          Logger.debug("State found in ETS: #{inspect(state)}")
          # restore the state from ETS
          {:ok, state}

        [] ->
          Logger.debug("No state found in ETS, creating new state")
          # No state found in ETS, create new state
          initial_state = %__MODULE__{
            peer_id: peer_id,
            crdt: crdt_text().new(peer_id),
            auto_saver: auto_saver().new(10, "./saves/" <> inspect(peer_id) <> ".txt")
          }

          # Store the initial state in the ETS table
          :ets.insert(@table_name, {peer_id, initial_state})
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

  def local_insert(index, value) do
    GenServer.cast(__MODULE__, {:local_insert, index, value})
  end

  def local_delete(index) do
    GenServer.cast(__MODULE__, {:local_delete, index})
  end

  def add_char(n) do
    total = n

    Enum.each(1..total, fn i ->
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
    ans = crdt_text().to_plain_text(state.crdt)
    {:reply, ans, state}
  end

  @impl true
  def handle_call({:get_crdt}, _from, state) do
    Logger.debug("Node #{inspect(state.peer_id)} is sending its crdt state!")
    {:reply, state.crdt, state}
  end

  @impl true
  def handle_cast({:upd_crdt, new_crdt}, state) do
    Logger.debug("Node #{inspect(state.peer_id)} is updating its crdt state!")

    new_crdt_with_id = %{
      new_crdt
      | peer_id: state.peer_id
    }

    new_saver = auto_saver().apply_state_update(state.auto_saver, new_crdt_with_id)

    ws_handler().send_init(crdt_text().to_plain_text(new_crdt_with_id))

    new_state = %__MODULE__{
      state
      | crdt: new_crdt_with_id,
        auto_saver: new_saver
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

    {pos_for_frontend, new_crdt} = crdt_text().apply_remote_insert(state.crdt, char)
    new_saver = auto_saver().apply_op(state.auto_saver, new_crdt)

    if pos_for_frontend do
      ws_handler().remote_insert(pos_for_frontend, char.value)
    end

    new_state = %__MODULE__{
      state
      | crdt: new_crdt,
        auto_saver: new_saver
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

    {pos_for_frontend, new_crdt} = crdt_text().apply_remote_delete(state.crdt, target_id)
    new_saver = auto_saver().apply_op(state.auto_saver, new_crdt)

    if pos_for_frontend do
      ws_handler().remote_delete(pos_for_frontend)
    end

    new_state = %__MODULE__{
      state
      | crdt: new_crdt,
        auto_saver: new_saver
    }

    # Store the updated state in ETS
    :ets.insert(@table_name, {state.peer_id, new_state})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:local_insert, index, value}, state) do
    Logger.debug("Node #{inspect(state.peer_id)} is applying the local insert at #{index}!")

    {new_char, new_crdt} = crdt_text().insert_local(state.crdt, index, value)
    new_saver = auto_saver().apply_op(state.auto_saver, new_crdt)

    new_state = %__MODULE__{
      state
      | crdt: new_crdt,
        auto_saver: new_saver
    }

    causal_broadcast().broadcast({:remote_insert, new_char})
    # Store the updated state in ETS
    :ets.insert(@table_name, {state.peer_id, new_state})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:local_delete, index}, state) do
    Logger.debug("Node #{inspect(state.peer_id)} is applying the local delete!")

    {target_id, new_crdt} = crdt_text().delete_local(state.crdt, index)
    new_saver = auto_saver().apply_op(state.auto_saver, new_crdt)

    new_state = %__MODULE__{
      state
      | crdt: new_crdt,
        auto_saver: new_saver
    }

    causal_broadcast().broadcast({:remote_delete, target_id})
    # Store the updated state in ETS
    :ets.insert(@table_name, {state.peer_id, new_state})
    {:noreply, new_state}
  end

  def handle_cast(_, state) do
    Logger.error("Message not valid!")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Terminating CRDT Manager process for node #{inspect(state.peer_id)} due to #{inspect(reason)}"
    )

    # placeholder for any cleanup tasks
    :ok
  end

  defp crdt_text() do
    Application.get_env(:p2p_docs, :crdt_text, CrdtText)
  end

  defp auto_saver() do
    Application.get_env(:p2p_docs, :auto_saver, AutoSaver)
  end

  defp causal_broadcast() do
    Application.get_env(:p2p_docs, :causal_broadcast, CausalBroadcast)[:module]
  end

  defp ws_handler() do
    Application.get_env(:p2p_docs, :ws_handler, Handler)
  end
end
