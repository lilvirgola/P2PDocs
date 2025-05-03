defmodule P2PDocs.Network.NeighborHandler do
  use GenServer
  require Logger
  @moduledoc """
  This module handles the discovery of neighbors in a peer-to-peer network using UDP multicast (lika a basic gossip algo).
  It sends periodic heartbeat messages to discover other peers and maintains a list of active peers.
  """
  ## Constants and Defaults, it gets the default values from the application config at compile time
  @default_port Application.compile_env(:p2p_docs, __MODULE__)[:port] || 45892
  @default_mcast_if Application.compile_env(:p2p_docs, __MODULE__)[:mcast_if] || {192, 168, 1, 1}
  @default_mcast_addr Application.compile_env(:p2p_docs, __MODULE__)[:mcast_addr] || {224, 1, 1, 1}
  @default_iface Application.compile_env(:p2p_docs, __MODULE__)[:iface] || {0, 0, 0, 0}
  @default_ttl Application.compile_env(:p2p_docs, __MODULE__)[:ttl] || 4
  @interval Application.compile_env(:p2p_docs, __MODULE__)[:interval] || 5_000
  @secret Application.compile_env(:p2p_docs, __MODULE__)[:secret] || "default"

  ## State Structure since it has a lot of fields, we define a struct for it
  defmodule State do
    @moduledoc """
    This struct represents the state of the NeighborHandler server.
    It includes the UDP socket, node name, list of peers, and other configuration parameters.
    """
    @enforce_keys [:socket, :peers] # enforce that socket and peers are always present
    defstruct [
      :socket,
      :node_name,
      peers: %{},
      subscribers: %{},
      port: 45892,  # Default value directly here
      mcast_addr: {224, 1, 1, 1},  # Default value directly here
      mcast_if: {192, 168, 1, 1},  # Default value directly here
      iface: {0, 0, 0, 0},  # Default value directly here
      ttl: 4,  # Default value directly here
      interval: 5_000,  # Default value directly here
      secret: "default"  # Default value directly here
    ]
  end

  @doc """
  Starts the NeighborHandler server with the given options.
  The options should include `:port`, `:mcast_addr`, `:mcast_if`, `:iface`, `:ttl`, `:interval`, and `:secret`.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Lists the currently known peers in the network.
  Each peer is represented as a map with `:name`, `:ip`, and `:port`.
  """
  def list_peers do
    GenServer.call(__MODULE__, :list_peers)
  end

  @doc """
  Subscribes the given process to receive notifications about peer discovery and expiration.
  The process will receive messages with the format `{:peer_discovered, peer}` or `{:peer_expired, peer}`.
  """
  def subscribe(pid \\ self()) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end

  @doc """
  Unsubscribes the given process from receiving notifications about peer discovery and expiration.
  The process will no longer receive messages with the format `{:peer_discovered, peer}` or `{:peer_expired, peer}`.
  """
  def unsubscribe(pid \\ self()) do
    GenServer.call(__MODULE__, {:unsubscribe, pid})
  end

  @doc """
  Initializes the NeighborHandler server with the given options.
  The options should include `:port`, `:mcast_addr`, `:mcast_if`, `:iface`, `:ttl`, `:interval`, and `:secret`.
  """
  @impl true # --> indicates that this function is an implementation of a callback defined in the GenServer behaviour more or less like @override in java
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)
    mcast_addr = Keyword.get(opts, :mcast_addr, @default_mcast_addr)
    mcast_if = Keyword.get(opts, :mcast_if, @default_mcast_if)
    iface = Keyword.get(opts, :iface, @default_iface)
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    interval = Keyword.get(opts, :interval, @interval)
    secret = Keyword.get(opts, :secret, @secret)

    node_name = Atom.to_string(node())

    # Create UDP socket
    {:ok, socket} = :gen_udp.open(port, [
      :binary,
      :inet,
      {:active, true},
      {:reuseaddr, true},
      {:multicast_if, mcast_if},
      {:multicast_loop, true},
      {:multicast_ttl, ttl},
      {:ip, iface},
      {:add_membership, {mcast_addr, iface}}
    ])

    # Schedule first heartbeat after the interval
    Process.send_after(self(), :send_heartbeat, interval)

    {:ok,
     %State{
        socket: socket,
        peers: %{},
        node_name: node_name,
        port: port,
        mcast_addr: mcast_addr,
        mcast_if: mcast_if,
        iface: iface,
        ttl: ttl,
        interval: interval,
        secret: secret,
        subscribers: %{}
     }}
  end
  @doc """
  Handles the heartbeat messages sent and recived to discover other peers in the network.
  It sends a heartbeat packet to the multicast address and updates the list of active peers.
  """
  @impl true
  def handle_info(:send_heartbeat, state) do
    heartbeat_packet = encode_heartbeat(state.node_name, state.secret)

    :gen_udp.send(
      state.socket,
      state.mcast_addr,
      state.port,
      heartbeat_packet
    )

    # Schedule next heartbeat
    Process.send_after(self(), :send_heartbeat, state.interval)

    # Remove old peers after 3 heartbeats
    now = System.monotonic_time(:second)
    {active_peers, expired_peers} = Enum.split_with(state.peers, fn {_, last_seen} ->
      now - last_seen < 3 * div(state.interval, 1000)
    end)
    # Notify about expired peers
    expired_peers
    |> Enum.map(fn {{name, ip, port}, _} -> %{name: name, ip: :inet.ntoa(ip), port: port} end) #map the expired items to a list of maps
    |> Enum.each(fn peer ->
      notify_subscribers(state.subscribers, {:peer_expired, peer}) #notify the subscribers about the expired peers
    end)

    {:noreply, %{state | peers: Map.new(active_peers)}}
  end

  @impl true
  def handle_info({:udp, _socket, ip, port, packet}, state) do
    case decode_heartbeat(packet, state.secret) do
      {:ok, peer_name} -> # If the packet is valid, we decode it and get the peer name
        if peer_name != state.node_name do
          Logger.debug("Received heartbeat from #{peer_name} at #{:inet.ntoa(ip)}:#{port}")

          peer_key = {peer_name, ip, port}
          now = System.monotonic_time(:second)

          # Check if this is a new peer
          is_new_peer = not Map.has_key?(state.peers, peer_key)

          # Update peers map
          peers = Map.put(state.peers, peer_key, now)

          # If it's a new peer, connect to it and notify subscribers
          if is_new_peer do
            peer = %{name: peer_name, ip: :inet.ntoa(ip), port: port}
            try do # try to convert the peer name to an existing atom, if doesn't exists, catch error and create a new atom
              node_atom = String.to_existing_atom(peer_name)
              case do_connect(node_atom) do
                {:ok, _} ->
                  Logger.info("Connected to new peer: #{peer_name}")
                {:error, _} ->
                  Logger.warning("Failed to connect to new peer: #{peer_name}")
              end
            rescue
              ArgumentError ->
                node_atom = String.to_atom(peer_name)
                case do_connect(node_atom) do
                  {:ok, _} ->
                    Logger.info("Connected to new peer: #{peer_name}")
                  {:error, _} ->
                    Logger.warning("Failed to connect to new peer: #{peer_name}")
                end
            end

            notify_subscribers(state.subscribers, {:peer_discovered, peer})
          end

          {:noreply, %{state | peers: peers}}
        else
          {:noreply, state}
        end

      :error -> # If the packet is invalid, we log a warning
        Logger.warning("Received invalid heartbeat packet from #{:inet.ntoa(ip)}:#{port}")
        {:noreply, state}
    end
  end

  ## if the process dies, we remove it from the subscribers list
  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case state.subscribers do
      %{^pid => ^ref} ->
        subscribers = Map.delete(state.subscribers, pid)
        {:noreply, %{state | subscribers: subscribers}}
      _ ->
        {:noreply, state}
    end
  end

  @doc """
  Handles the call to the module, which is used to list the peers in the network, handle subscriptions and unsubscriptions.
  """
  @impl true
  def handle_call(:list_peers, _from, state) do
    peers =
      state.peers
      |> Map.keys()
      |> Enum.map(fn {name, ip, port} -> %{name: name, ip: :inet.ntoa(ip), port: port} end)

    {:reply, peers, state}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    ref = Process.monitor(pid)
    subscribers = Map.put(state.subscribers, pid, ref)
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    case Map.pop(state.subscribers, pid) do
      {nil, _} ->
        {:reply, {:error, :not_subscribed}, state}
      {ref, subscribers} ->
        Process.demonitor(ref)
        {:reply, :ok, %{state | subscribers: subscribers}}
    end
  end

  @doc """
  Handles the termination of the server.
  It closes the UDP socket and cleans up any resources.
  """
  @impl true
  def terminate(_reason, state) do
    :gen_udp.close(state.socket)
  end

  ## Private functions
  # @doc """
  # Notifies all subscribers about the discovery or expiration of a peer.
  # Each subscriber will receive a message with the format `{:peer_discovered, peer}` or `{:peer_expired, peer}`.
  # """
  defp notify_subscribers(subscribers, message) do
    Enum.each(subscribers, fn {pid, _ref} ->
      send(pid, message)
    end)
  end

  # @doc """
  # Encodes the heartbeat message to be sent to the multicast address.
  # The message includes the node name and a timestamp.
  # The message is serialized using Erlang's term_to_binary function.
  # """
  defp encode_heartbeat(node_name, _secret) do
    payload = :erlang.term_to_binary(%{node: node_name, timestamp: System.system_time(:second)})
    # TODO: encrypt the payload with the secret, for now we just send it as is
    encrypted = payload
    <<byte_size(encrypted)::32, encrypted::binary>>
  end

  # @doc """
  # Decodes the heartbeat message received from the multicast address.
  # The message is expected to be in the format <<size::32, encrypted::binary-size(size)>>.
  # The size is the length of the encrypted payload, and the payload is deserialized using Erlang's binary_to_term function.
  # """
  defp decode_heartbeat(<<size::32, encrypted::binary-size(size)>>, _secret) do
    try do
      # TODO: decrypt the payload with the secret, for now we it is as is
      payload = encrypted
      %{node: node_name} = :erlang.binary_to_term(payload)
      {:ok, node_name}
    rescue
      _ -> :error
    end
  end

  # @doc """
  # Handles malformed packets that do not match the expected format.
  # returns an error.
  defp decode_heartbeat(_malformed, _secret), do: :error

  # @doc """
  # Attempts to connect to a node using its atom name.
  # If the connection is successful, it returns `{:ok, node_atom}`.
  # If the connection fails, it returns `{:error, :connection_failed}`.
  # """
  defp do_connect(node_atom) do
    case Node.connect(node_atom) do
      true -> {:ok, node_atom}
      false -> {:error, :connection_failed}
    end
  end
end
