defmodule P2PDocs.Network.CausalBroadcast do
  use GenServer
  alias P2PDocs.Network.NaiveVectorClock, as: VectorClock # this can be replaced with a more efficient implementation later
  require Logger
  @moduledoc """
  This module implements our causal broadcast protocol using vector clocks.
  """

  defmodule State do
    @moduledoc """
    This struct represents the state of the CausalBroadcast server.
    It includes the vector clock, delivery counters, and pending messages.
    """
    defstruct [
      :my_id,
      :nodes,
      t: %{}, # Vector clock
      d: %{}, # Delivery counters
      buffer: MapSet.new(), # Pending messages
      delivery_pid: nil # Where to send delivery notifications (added for the tests)
    ]
  end

  @doc """
  Starts the CausalBroadcast server with the given options.
  The options should include `:my_id` (the ID of the current node) and `:nodes` (a list of known nodes).
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Broadcasts a message to all known nodes.
  The message is sent as a cast to the server.
  """
  def broadcast(msg) do
    GenServer.cast(__MODULE__, {:broadcast, msg})
  end

  @doc """
  Retrieves the current state of the CausalBroadcast server.
  The state includes the vector clock, delivery counters, and pending messages.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Adds a new node to the list of known nodes.
  The new node is added to the list of nodes and its vector clock is initialized.
  """
  def add_node(server \\ __MODULE__, new_node) do
    GenServer.call(server, {:add_node, new_node})
  end

  @doc """
  Removes a node from the list of known nodes.
  The node is removed from the list of nodes and its vector clock is reset.
  """
  def remove_node(server \\ __MODULE__, old_node) do
    GenServer.call(server, {:add_node, old_node})
  end

  @doc """
  Initializes the CausalBroadcast server with the given options.
  The options should include `:my_id` (the ID of the current node) and `:nodes` (a list of known nodes).
  """
  @impl true # --> indicates that this function is an implementation of a callback defined in the GenServer behaviour more or less like @override in java
  def init(opts) do
    my_id = Keyword.fetch!(opts, :my_id)
    initial_nodes = Keyword.get(opts, :nodes, [my_id]) |> Enum.uniq()
    # Subscribe to neighbor events
    :ok = P2PDocs.Network.NeighborHandler.subscribe(self())
    # Initialize the state with the given options
    {:ok, %State{
      my_id: my_id, # Our node ID
      nodes: initial_nodes,
      t: VectorClock.new(my_id), # Our vector clock (t)
      d: VectorClock.new(), # Delivery counters (d) as VectorClock
      buffer: MapSet.new(), # Pending messages
      delivery_pid: Keyword.get(opts, :delivery_pid, self()) # Where to send delivery notifications (added for the tests)
    }}
  end
  # Handle info messages from the neighbor handler part

  @doc """
  Handles incoming messages from the neighbor handler.
  This includes messages about discovered and expired peers.
  """
  @impl true
  def handle_info({:peer_discovered, %{name: node_name} = peer}, state) do
    Logger.info("Peer discovered: #{inspect(peer)}")
    new_node = String.to_existing_atom(node_name)
    GenServer.cast(__MODULE__, {:add_node, new_node})
    {:noreply, state}
  end

  @impl true
  def handle_info({:peer_expired, %{name: node_name} = peer}, state) do
    Logger.info("Peer expired: #{inspect(peer)}")
    old_node = String.to_existing_atom(node_name)
    GenServer.cast(__MODULE__, {:remove_node, old_node})
    {:noreply, state}
  end

  # Handle cast messages for broadcasting and receiving messages

  @doc """
  Handles the main logic of the causal broadcast protocol.
  This includes broadcasting messages, receiving messages, managing the state of the vector clocks and adding and removing nodes.
  """
  @impl true
  def handle_cast({:broadcast, msg}, state) do
    new_t = VectorClock.increment(state.t, state.my_id)
    Logger.debug("[#{node()}] BROADCASTING #{inspect(msg)} with VC: #{inspect(new_t)}")

    for node <- state.nodes do
      GenServer.cast({__MODULE__, node}, {:message, msg, state.my_id, new_t})
    end

    {:noreply, %{state | t: new_t}}
  end

  @impl true
  def handle_cast({:message, msg, id, t_prime}, state) do
    Logger.debug("[#{node()}] RECEIVED #{inspect(msg)} from #{inspect(id)} with VC: #{inspect(t_prime)}")
    new_t = VectorClock.merge(state.t, t_prime)
    new_buffer = MapSet.put(state.buffer, {msg, id, t_prime})

    {delivered, remaining_buffer, new_d} =
      attempt_deliveries(new_buffer, state.d, new_t, id)

    for {delivered_msg, delivered_id, delivered_t} <- delivered do
      handle_delivery(msg)
      Logger.info("[#{node()}] DELIVERED #{inspect(delivered_msg)} from #{inspect(delivered_id)} with VC: #{inspect(delivered_t)}")
    end

    {:noreply, %{
      state |
      t: new_t,
      d: new_d,
      buffer: remaining_buffer
    }}
  end

  @impl true
  def handle_cast({:add_node, new_node}, state) do
    if new_node in state.nodes do
      {:noreply, state}  # Already exists
    else
      # Initialize clocks for new node WITHOUT incrementing
      new_t = VectorClock.merge(state.t, VectorClock.new(new_node))
      new_d = VectorClock.merge(state.d, VectorClock.new(new_node))

      {:noreply, %{state |
        nodes: [new_node | state.nodes],
        t: new_t,
        d: new_d
      }}
    end
  end

  # Handle removal of nodes,
  @impl true
  def handle_cast({:remove_node, old_node}, state) do
    if old_node in state.nodes do
      {:noreply, %{state |
        nodes: List.delete(state.nodes, old_node),
        d: VectorClock.merge(state.d, VectorClock.new(old_node)) # Reset delivery counter for removed node? ## TODO: Check if this is correct
      }}
    else
      {:noreply, state}
    end
  end

  # Handle synchronous calls to get the state of the server
  @doc """
  Handles synchronous calls to get the state of the server.
  This includes the vector clock, delivery counters, and pending messages.
  """
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, %{
      vector_clock: state.t,
      delivery_counters: state.d,
      pending_messages: state.buffer
    }, state}
  end

  # Private helper functions
  # @doc """
  # Attempts to deliver messages from the buffer based on the causal delivery conditions.
  # This function checks if the messages in the buffer can be delivered based on the vector clocks and the current state.

  # """
  defp attempt_deliveries(buffer, d, current_t, my_id) do # TODO: Check if this is correct, should be, like in the slides, but idk
    # For each message in the buffer, check if it can be delivered
    Enum.reduce(buffer, {[], buffer, d}, fn {msg, sender_id, t_prime}, {delivered, remaining, d_acc} ->
      cond do
        # Case 1: Message is from myself - deliver immediately
        sender_id == my_id ->
          new_d = VectorClock.increment(d_acc, my_id)
          {[{msg, sender_id, t_prime} | delivered],
           MapSet.delete(remaining, {msg, sender_id, t_prime}),
           new_d}


        # Case 2: Message passes causal delivery condition
        deliverable?(t_prime, sender_id, d_acc, current_t) ->
          new_d = VectorClock.increment(d_acc, sender_id)
          {[{msg, sender_id, t_prime} | delivered],
           MapSet.delete(remaining, {msg, sender_id, t_prime}),
           new_d}

        # Case 3: Not deliverable yet
        true ->
          {delivered, remaining, d_acc}
      end
    end)

  end

  # @doc """
  # Checks if a message can be delivered based on the causal delivery conditions.
  # This function checks if the message's vector clock is less than or equal to the current vector clock and the delivery counter.
  # """
  defp deliverable?(t_prime, sender_id, d, current_t) do # TODO: Check if this is correct, same as above
    # Check if t_prime <= current_t (message is within our known timeline)
    time_ok = VectorClock.before?(t_prime, current_t) or VectorClock.concurrent?(t_prime, current_t)

    # Check if t_prime <= d' = d[sender_id] + 1
    d_prime = VectorClock.increment(d, sender_id)
    counter_ok = VectorClock.before?(t_prime, d_prime) or VectorClock.concurrent?(t_prime, d_prime)

    time_ok and counter_ok
  end

  # @doc """
  # Handles the actual delivery of a message.
  # """
  defp handle_delivery(msg) do
    # Placeholder for actual delivery logic
    Logger.info("Delivering message: #{inspect(msg)}")
  end
end
