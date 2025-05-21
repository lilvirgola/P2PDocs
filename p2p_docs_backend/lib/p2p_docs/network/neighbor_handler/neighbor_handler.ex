defmodule P2PDocs.Network.NeighborHandler do
  use GenServer
  require Logger
  alias P2PDocs.Network.EchoWave
  alias P2PDocs.CRDT.Manager
  alias P2PDocs.Network.CausalBroadcast
  alias P2PDocs.Network.ReliableTransport

  @moduledoc """
  This module is responsible for handling the neighbors of a node in the P2P network.
  It manages the state of the neighbors and handles join and leave requests.
  It uses ETS for storing the state of the neighbors.
  The state is stored in an ETS table, which allows for fast access and updates.
  """

  @table_name Application.compile_env(:p2p_docs, :neighbor_handler)[:ets_table] ||
                :neighbor_handler_state

  # GenServer API
  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: __MODULE__)
  end

  def get_neighbors() do
    GenServer.call(__MODULE__, :get_neighbors)
  end

  @impl true
  def init(my_id) do
    Logger.debug("Starting NeighborHandler module for node #{inspect(my_id)}")
    Process.flag(:trap_exit, true)

    try do
      case :ets.lookup(@table_name, my_id) do
        [{_key, state}] ->
          # State found in ETS, return it
          Logger.debug("State found in ETS: #{inspect(state)}")
          # restore the state from ETS
          {:ok, state}

        [] ->
          Logger.debug("No state found in ETS, creating new state")
          # No state found in ETS, create new state
          initial_state = %{
            peer_id: my_id,
            neighbors: []
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

  # Handles a join request from a peer
  @impl true
  def handle_cast({:join, peer_id, asked}, state) do
    Logger.debug("Node #{inspect(peer_id)} is trying to join the network.")

    if state.peer_id == peer_id do
      Logger.debug("I am node #{inspect(peer_id)}, why should i add myself.")
      {:noreply, state}
    else
      if Enum.member?(state.neighbors, peer_id) do
        if asked == :no_ask do
          Logger.debug("Node #{inspect(peer_id)} is already a neighbor.")
          {:noreply, state}
        else
          Logger.debug("Node #{inspect(peer_id)} is already a neighbor, but asked to update.")

          ReliableTransport.send(
            state.peer_id,
            peer_id,
            Manager,
            {:upd_crdt, Manager.get_state()}
          )

          ReliableTransport.send(
            state.peer_id,
            peer_id,
            CausalBroadcast,
            {:upd_vc_and_d, CausalBroadcast.get_vc_and_d_state()}
          )
        end

        # update the frontend
        P2PDocs.API.WebSocket.Handler.send_init()
        # If the node is already a neighbor, just return the state
        {:noreply, state}
      else
        new_neighbors = [peer_id | state.neighbors]
        EchoWave.update_neighbors(new_neighbors)
        Logger.info("Node #{inspect(peer_id)} joined the network.")

        if asked == :ask do
          ReliableTransport.send(
            state.peer_id,
            peer_id,
            Manager,
            {:upd_crdt, Manager.get_state()}
          )

          ReliableTransport.send(
            state.peer_id,
            peer_id,
            CausalBroadcast,
            {:upd_vc_and_d, CausalBroadcast.get_vc_and_d_state()}
          )
        end

        # update the frontend
        P2PDocs.API.WebSocket.Handler.send_init()
        new_state = %{state | neighbors: new_neighbors}
        # Store the updated state in ETS
        :ets.insert(@table_name, {state.peer_id, new_state})
        {:noreply, new_state}
      end
    end
  end

  # Handles a leave request from a peer
  @impl true
  def handle_cast({:leave, peer_id}, state) do
    if not Enum.member?(state.neighbors, peer_id) do
      Logger.debug("Node #{inspect(peer_id)} is already not a neighbor.")
      {:noreply, state}
    else
      new_neighbors = List.delete(state.neighbors, peer_id)
      EchoWave.update_neighbors(new_neighbors)
      Logger.info("Node #{inspect(peer_id)} leaved the network.")
      new_state = %{state | neighbors: new_neighbors}
      # update the frontend
      P2PDocs.API.WebSocket.Handler.send_init()
      # Store the updated state in ETS
      :ets.insert(@table_name, {state.peer_id, new_state})
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:leave_all}, state) do
    for {neighbor1, i} <- Enum.with_index(state.neighbors) do
      for {neighbor2, j} <- Enum.with_index(state.neighbors) do
        if j > i do
          ReliableTransport.send(
            state.peer_id,
            neighbor1,
            __MODULE__,
            {:join, neighbor2, :no_ask}
          )

          ReliableTransport.send(
            state.peer_id,
            neighbor2,
            __MODULE__,
            {:join, neighbor1, :no_ask}
          )
        end
      end
    end

    for neighbor <- state.neighbors do
      remove_neighbor(neighbor)
    end

    # update the frontend
    P2PDocs.API.WebSocket.Handler.send_init()
    {:noreply, state}
  end

  @impl true
  def handle_cast(_, state) do
    Logger.error("Message not valid!")
    {:noreply, state}
  end

  @callback join(peer_id :: any) :: :ok | {:error, any}
  def join(peer_id) do
    case Node.connect(peer_id) do
      true ->
        GenServer.cast(__MODULE__, {:join, peer_id, :no_ask})

        ReliableTransport.send(
          node(),
          peer_id,
          __MODULE__,
          {:join, node(), :ask}
        )

        :ok

      false ->
        Logger.debug("Failed to connect to peer #{inspect(peer_id)}")
        {:error, "Failed to connect to peer"}

      :ignored ->
        Logger.debug("Peer #{inspect(peer_id)} is already connected")
        {:error, "Peer already connected"}
    end
  end

  @callback add_neighbor(peer_id :: any) :: :ok | {:error, any}
  def add_neighbor(peer_id) do
    case Node.connect(peer_id) do
      true ->
        GenServer.cast(__MODULE__, {:join, peer_id, :no_ask})

        ReliableTransport.send(
          node(),
          peer_id,
          __MODULE__,
          {:join, node(), :no_ask}
        )

      false ->
        Logger.debug("Failed to connect to peer #{inspect(peer_id)}")
        {:error, "Failed to connect to peer"}

      :ignored ->
        Logger.debug("Peer #{inspect(peer_id)} is already connected")
        {:error, "Peer already connected"}
    end
  end

  @callback remove_neighbor(peer_id :: any) :: :ok | {:error, any}
  def remove_neighbor(peer_id) do
    case Node.disconnect(peer_id) do
      true ->
        GenServer.cast(__MODULE__, {:leave, peer_id})

        ReliableTransport.send(
          node(),
          peer_id,
          __MODULE__,
          {:leave, node()}
        )

        :ok

      false ->
        Logger.debug("Failed to disconnect to peer #{inspect(peer_id)}")
        {:error, "Failed to disconnect from peer"}

      :ignored ->
        Logger.debug("Peer #{inspect(peer_id)} is already disconnected")
        {:error, "Peer already disconnected"}
    end
  end

  @callback leave() :: :ok
  def leave() do
    GenServer.cast(__MODULE__, {:leave_all})
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Terminating NeighborHandler process for node #{inspect(state.peer_id)} due to #{inspect(reason)}"
    )

    for {neighbor1, i} <- Enum.with_index(state.neighbors) do
      for {neighbor2, j} <- Enum.with_index(state.neighbors) do
        if j > i do
          ReliableTransport.send(
            state.peer_id,
            neighbor1,
            __MODULE__,
            {:join, neighbor2, :no_ask}
          )

          ReliableTransport.send(
            state.peer_id,
            neighbor2,
            __MODULE__,
            {:join, neighbor1, :no_ask}
          )
        end
      end
    end

    for neighbor <- state.neighbors do
      remove_neighbor(neighbor)
    end

    :ok
  end

  @impl true
  def handle_call(:get_neighbors, _from, state) do
    {:reply, state.neighbors, state}
  end
end
