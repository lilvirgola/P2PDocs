defmodule P2PDocs.Network.NeighborHandler do
 use GenServer
 require Logger
 alias P2PDocs.Network.EchoWave

 @table_name Application.compile_env(:p2p_docs, :neighbor_handler)[:ets_table] ||
                :neighbor_handler_state


 # GenServer API
  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: __MODULE__)
  end

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

  def get_neighbors do
    GenServer.call(__MODULE__, :get_neighbors)
  end

 # Handles a join request from a peer
 def handle_cast({:join, peer_id}, state) do
  if Enum.member?(state.neighbors, peer_id) do
      Logger.debug("Node #{inspect(peer_id)} is already a neighbor.")
      {:noreply, state}
  else
      new_neighbors = [peer_id | state.neighbors]
      EchoWave.update_neighbors(new_neighbors)
      Logger.debug("Node #{inspect(peer_id)} joined the network.")
      new_state = %{state | neighbors: new_neighbors}
      # Store the updated state in ETS
      :ets.insert(@table_name, {state.peer_id, new_state})
      {:noreply, new_state}
  end
 end

 # Handles a leave request from a peer
  def handle_cast({:leave, peer_id}, state) do
    if not Enum.member?(state.neighbors, peer_id) do
      Logger.debug("Node #{inspect(peer_id)} is already not a neighbor.")
      {:noreply, state}
    else
      new_neighbors = List.delete(state.neighbors, peer_id)
      EchoWave.update_neighbors(new_neighbors)
      Logger.debug("Node #{inspect(peer_id)} joined the network.")
      new_state = %{state | neighbors: new_neighbors}
      # Store the updated state in ETS
      :ets.insert(@table_name, {state.peer_id, new_state})
      {:noreply, new_state}
    end
  end

 def add_neighbor(peer_id) do
   case Node.connect(peer_id) do
     true ->
        GenServer.cast(__MODULE__, {:join, peer_id})
        GenServer.cast({__MODULE__, peer_id}, {:join, node()})
       :ok
     false ->
       Logger.debug("Failed to connect to peer #{inspect(peer_id)}")
       {:error, "Failed to connect to peer"}
     :ignored ->
       Logger.debug("Peer #{inspect(peer_id)} is already connected")
       {:error, "Peer already connected"}
   end
    # Add the peer to the list of neighbo
 end

 def remove_neighbor(peer_id) do
   case Node.disconnect(peer_id) do
     true ->
        GenServer.cast(__MODULE__, {:leave, peer_id})
        GenServer.cast({__MODULE__, peer_id}, {:leave, node()})
        :ok
     false ->
        Logger.debug("Failed to disconnect to peer #{inspect(peer_id)}")
        {:error, "Failed to disconnect from peer"}
      :ignored ->
        Logger.debug("Peer #{inspect(peer_id)} is already disconnected")
        {:error, "Peer already disconnected"}
   end

 end
end
