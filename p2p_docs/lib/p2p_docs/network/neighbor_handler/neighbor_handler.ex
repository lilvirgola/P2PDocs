defmodule P2PDocs.Network.NeighborHandler do
 use GenServer
 require Logger
 alias P2PDocs.Network.EchoWave


 # GenServer API
  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: __MODULE__)
  end

  def init(peer_id) do
    state = %{
      peer_id: peer_id,
      neighbors: []
    }
    {:ok, state}
  end

  def get_neighbors do
    GenServer.call(__MODULE__, :get_neighbors)
  end

 # Handles a join request from a peer
 def handle_cast({:join, peer_id}, state) do
  if Enum.member?(state.neighbors, peer_id) do
      Logger.debug("Node #{inspect(peer_id)} is already a neighbor.")
      {:noreply, state}
    end
    new_neighbors = [peer_id | state.neighbors]
    EchoWave.update_neighbors(new_neighbors)
    Logger.debug("Node #{inspect(peer_id)} joined the network.")
    {:noreply, %{state | neighbors: new_neighbors}}
 end

 # Handles a leave request from a peer
  def handle_cast({:leave, peer_id}, state) do
    if not Enum.member?(state.neighbors, peer_id) do
      Logger.debug("Node #{inspect(peer_id)} is already not a neighbor.")
      {:noreply, state}
    end
    new_neighbors = List.delete(state.neighbors, peer_id)
    EchoWave.update_neighbors(new_neighbors)
    Logger.debug("Node #{inspect(peer_id)} joined the network.")
    {:noreply, %{state | neighbors: new_neighbors}}
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
