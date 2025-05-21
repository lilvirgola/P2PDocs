defmodule P2PDocs.CRDT.Manager do
  @moduledoc """
  Manages the CRDT state for a peer, broadcasts local changes, applies remote operations,
  and persists state in ETS and via an AutoSaver.
  """
  use GenServer
  require Logger

  alias P2PDocs.Network.CausalBroadcast
  alias P2PDocs.CRDT.{CrdtText, AutoSaver}
  alias P2PDocs.API.WebSocket.Handler

  # ETS table where the manager state is stored
  @table_name Application.compile_env(:p2p_docs, :crdt_manager)[:ets_table] || :crdt_manager_state

  defstruct peer_id: nil,
            crdt: nil,
            auto_saver: nil

  ## Public API

  @doc """
  Starts the CRDT Manager for the given peer.
  """
  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: __MODULE__)
  end

  @doc """
  Sends a generic message to the manager.
  """
  def receive(msg), do: GenServer.cast(__MODULE__, msg)

  @doc """
  Fetches the plain-text representation of the CRDT.
  """
  def print_state, do: GenServer.call(__MODULE__, :get_state)

  @doc """
  Returns the raw CRDT struct.
  """
  def get_state, do: GenServer.call(__MODULE__, :get_crdt)

  @doc """
  Inserts a local character at the given index.
  """
  def local_insert(index, value), do: GenServer.cast(__MODULE__, {:local_insert, index, value})

  @doc """
  Deletes a local character at the given index.
  """
  def local_delete(index), do: GenServer.cast(__MODULE__, {:local_delete, index})

  @doc """
  Inserts `n` dummy characters incrementally at random positions.
  Useful for testing performance.
  """
  def add_char(n) when is_integer(n) and n > 0 do
    for i <- 1..n do
      idx = :rand.uniform(i)
      GenServer.cast(__MODULE__, {:local_insert, idx, "a#{i}"})
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(peer_id) do
    Logger.debug("Starting CRDT Manager for node #{inspect(peer_id)}")
    Process.flag(:trap_exit, true)

    # Attempt to restore state from ETS, or initialize a new one
    case safe_ets_lookup(peer_id) do
      {:ok, state} ->
        Logger.debug("Restored state from ETS: #{inspect(state)}")
        {:ok, state}

      :not_found ->
        Logger.debug("No existing ETS state, creating new state")
        state = build_initial_state(peer_id)
        :ets.insert(@table_name, {peer_id, state})
        {:ok, state}

      {:error, :badarg} ->
        Logger.error("ETS table #{@table_name} not found")
        {:stop, :badarg}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    # Return plain text of CRDT
    text = CrdtText.to_plain_text(state.crdt)
    {:reply, text, state}
  end

  @impl true
  def handle_call(:get_crdt, _from, state) do
    Logger.debug("Sending raw CRDT for #{state.peer_id}")
    {:reply, state.crdt, state}
  end

  @impl true
  def handle_cast({:local_insert, idx, val}, state) do
    Logger.debug("Local insert at #{idx}")

    {char, new_crdt} = CrdtText.insert_local(state.crdt, idx, val)
    new_saver = AutoSaver.apply_op(state.auto_saver, new_crdt)

    # Broadcast to other peers
    CausalBroadcast.broadcast({:remote_insert, char})

    # Persist and update state
    state = update_state(state, new_crdt, new_saver)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:local_delete, idx}, state) do
    Logger.debug("Local delete at #{idx}")

    {target_id, new_crdt} = CrdtText.delete_local(state.crdt, idx)
    new_saver = AutoSaver.apply_op(state.auto_saver, new_crdt)

    CausalBroadcast.broadcast({:remote_delete, target_id})
    state = update_state(state, new_crdt, new_saver)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:remote_insert, char}, state) do
    Logger.debug("Applying remote insert of #{inspect(char)}")

    {pos, new_crdt} = CrdtText.apply_remote_insert(state.crdt, char)
    new_saver = AutoSaver.apply_op(state.auto_saver, new_crdt)

    # Notify frontend if needed
    if pos, do: Handler.remote_insert(pos, char.value)

    state = update_state(state, new_crdt, new_saver)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:remote_delete, target}, state) do
    Logger.debug("Applying remote delete of #{inspect(target)}")

    {pos, new_crdt} = CrdtText.apply_remote_delete(state.crdt, target)
    new_saver = AutoSaver.apply_op(state.auto_saver, new_crdt)

    if pos, do: Handler.remote_delete(pos)

    state = update_state(state, new_crdt, new_saver)
    {:noreply, state}
  end

  @impl true
  def handle_cast(_, state) do
    Logger.error("Received invalid cast message")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Terminating CRDT Manager #{inspect(state.peer_id)}: #{inspect(reason)}")
    :ok
  end

  ## Internal Helpers

  # Safely lookup ETS entry
  defp safe_ets_lookup(peer_id) do
    try do
      case :ets.lookup(@table_name, peer_id) do
        [{^peer_id, state}] -> {:ok, state}
        [] -> :not_found
      end
    catch
      :error, :badarg -> {:error, :badarg}
    end
  end

  # Build a fresh manager state
  defp build_initial_state(peer_id) do
    %__MODULE__{
      peer_id: peer_id,
      crdt: CrdtText.new(peer_id),
      auto_saver: AutoSaver.new(10, "./saves/#{peer_id}.txt")
    }
  end

  # Update ETS and return new state struct
  defp update_state(state, new_crdt, new_saver) do
    new_state = %__MODULE__{state | crdt: new_crdt, auto_saver: new_saver}
    :ets.insert(@table_name, {state.peer_id, new_state})
    new_state
  end
end
