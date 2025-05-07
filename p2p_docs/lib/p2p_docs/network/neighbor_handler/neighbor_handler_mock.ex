defmodule P2PDocs.Network.NeighborHandlerMock do
  use GenServer
  require Logger

  @moduledoc """
  This module handles the discovery of neighbors in a peer-to-peer network using UDP multicast (lika a basic gossip algo).
  It sends periodic heartbeat messages to discover other peers and maintains a list of active peers.
  """

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
  # --> indicates that this function is an implementation of a callback defined in the GenServer behaviour more or less like @override in java
  @impl true
  def init(_opts) do
    {:ok, []}
  end

  @doc """
  Handles the call to the module, which is used to list the peers in the network, handle subscriptions and unsubscriptions.
  """
  @impl true
  def handle_call(:list_peers, _from, state) do

    {:reply, [], state}
  end

  @impl true
  def handle_call({:subscribe, _pid}, _from, _state) do
    {:reply, :ok, []}
  end

  @impl true
  def handle_call({:unsubscribe, _pid}, _from, _state) do
    {:reply, :ok, []}
  end

  @doc """
  Handles the termination of the server.
  It closes the UDP socket and cleans up any resources.
  """
  @impl true
  def terminate(_reason, _state) do
    :ok
  end

end
