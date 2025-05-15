defmodule P2PDocs.Network.NeighborHandler do
  require Logger
  alias P2PDocs.Network.EchoWave

  def add_neighbor(peer_id) do
    case Node.connect(peer_id) do
      true ->
        EchoWave.add_neighbors(node(), [{peer_id, peer_id}])
        :ok
      false ->
        Logger.debug("Failed to connect to peer #{inspect(peer_id)}")
        {:error, "Failed to connect to peer"}
      :ignored ->
        Logger.debug("Peer #{inspect(peer_id)} is already connected")
        {:error, "Peer already connected"}
    end
  end
  def remove_neighbor(peer_id) do
    case Node.disconnect(peer_id) do
      true ->
        EchoWave.del_neighbors(node(), [{peer_id, peer_id}])
        :ok
      false ->
        {:error, "Failed to disconnect from peer"}
    end
    :ok
  end

end
