defmodule P2PDocs.API.WebSocket.Handler do
  require Logger
  alias P2PDocs.CRDT.Manager
  alias P2PDocs.PubSub

  def init(req, state) do
    {:cowboy_websocket, req, state}
  end

  def remote_insert(index, value) do
    # Send a message to the client
    msg = %{
      type: "insert",
      index: index,
      char: value
    }

    PubSub.broadcast(msg)
  end

  def remote_delete(index) do
    # Send a message to the client
    msg = %{
      type: "delete",
      index: index
    }

    PubSub.broadcast(msg)
  end

  def websocket_init(state) do
    # Initialize state with empty map if not provided
    Process.send_after(self(), :send_ping, 30_000)
    PubSub.subscribe(self())
    send_initial_message(state)
    {:ok, Map.new(state || %{})}
  end

  def websocket_handle({:text, message}, state) do
    case Jason.decode(message) do
      {:ok, decoded} ->
        # Handle JSON message
        handle_message(decoded, state)

      {:error, _reason} ->
        # Handle plain text message
        Logger.debug("Received plain text message: #{message}")
        {:reply, {:text, "Received: #{message}"}, state}
    end
  end

  def websocket_handle(_other, state) do
    # Handle other types of messages (binary, ping, pong)
    {:ok, state}
  end

  def websocket_info(:send_ping, state) do
    Process.send_after(self(), :send_ping, 30_000)
    {:reply, {:text, "{\"type\":\"ping\"}"}, state}
  end

  def websocket_info({:send, msg}, state) do
    operation = %{
      type: "operations",
      operations: msg
    }

    {:reply, {:text, Jason.encode!(operation)}, state}
  end

  def websocket_info(_info, state) do
    {:ok, state}
  end

  def terminate(_reason, _req, _state) do
    PubSub.unsubscribe(self())
    :ok
  end

  defp handle_message(%{"type" => "ping"}, state) do
    Logger.debug("keeping alive")
    {:reply, {:text, "{\"type\":\"pong\"}"}, state}
  end

  defp handle_message(%{"type" => "get_client_id"}, state) do
    send_initial_message(state)
  end

  defp handle_message(%{"type" => "pong"}, state) do
    {:reply, {:text, "{\"type\":\"ok\"}"}, state}
  end

  defp handle_message(
         %{
           "char" => char,
           "client_id" => _client_id,
           "index" => index,
           "type" => "insert"
         },
         state
       ) do
    Manager.local_insert(index, char)
    {:reply, {:text, "{\"type\":\"ok\"}"}, state}
  end

  defp handle_message(
         %{"client_id" => _client_id, "index" => index, "type" => "delete"},
         state
       ) do
    if index != "marker" do
      Manager.local_delete(index)
    end

    {:reply, {:text, "{\"type\":\"ok\"}"}, state}
  end

  defp handle_message(
         %{"type" => "disconnect", "peer_id" => _peer_id},
         state
       ) do
    # remove neighbor but for now just leave all neighbors
    # P2PDocs.Network.NeighborHandler.remove_neighbor(peer_id)
    P2PDocs.Network.NeighborHandler.leave()

    {:reply, {:text, "{\"type\":\"ok\"}"}, state}
  end

  defp handle_message(
         %{"type" => "disconnect"},
         state
       ) do
    # leave all neighbors
    P2PDocs.Network.NeighborHandler.leave()

    {:reply, {:text, "{\"type\":\"ok\"}"}, state}
  end

  defp handle_message(
         %{"client_id" => _client_id, "index" => index, "type" => "delete"},
         state
       ) do
    if index != "marker" do
      Manager.local_delete(index)
    end

    {:reply, {:text, "{\"type\":\"ok\"}"}, state}
  end

  defp handle_message(%{"peer_address" => peer_addr, "type" => "connect"}, state) do
    case safe_to_atom(peer_addr) do
      {:ok, peer_node} ->
        # Connect to the peer node
        case P2PDocs.Network.NeighborHandler.join(peer_node) do
          :ok ->
            # Send a message to the peer node
            P2PDocs.Network.NeighborHandler.add_neighbor(peer_node)
            Logger.info("Connected to peer: #{peer_addr}")
            {:reply, {:text, "{\"type\":\"ok\"}"}, state}

          {:error, reason} ->
            Logger.error("Failed to connect to peer #{peer_addr}: #{inspect(reason)}")
            {:reply, {:text, "{\"type\":\"error\", \"message\":\"invalid_peer_address\"}"}, state}
        end

      {:error, _reason} ->
        Logger.error("Invalid peer address format: #{peer_addr}")
        {:reply, {:text, "{\"type\":\"error\", \"message\":\"invalid_peer_address\"}"}, state}
    end
  end

  defp handle_message(unknown, state) do
    Logger.debug("Received unknown message format: #{inspect(unknown)}")
    {:reply, {:text, "{\"error\":\"unknown_message_format\"}"}, state}
  end

  defp send_initial_message(state) do
    crdt = P2PDocs.CRDT.Manager.get_state()
    # Get the CRDT state from the CRDT Manager
    text =
      if crdt != nil do
        P2PDocs.CRDT.CrdtText.to_plain_text(crdt) |> Enum.join("")
      else
        ""
      end

    Logger.debug("Sending initial message to client: #{inspect(text)}")

    initial_message = %{
      type: "init",
      content: text,
      client_id: node()
    }

    {:reply, {:text, Jason.encode!(initial_message)}, state}
  end

  defp safe_to_atom(peer_addr) do
    if Regex.match?(~r/^[a-zA-Z0-9_]+@(?:\d{1,3}\.){3}\d{1,3}$/, peer_addr) do
      peer_node = String.to_atom(peer_addr)
      {:ok, peer_node}
    else
      {:error, :invalid_node_name}
    end
  end
end
