defmodule P2PDocs.Network.CausalBroadcast do
  use GenServer

  # this can be replaced with a more efficient implementation later
  alias P2PDocs.Network.NaiveVectorClock, as: VectorClock
  alias P2PDocs.Network.EchoWave
  require Logger

  @table_name Application.compile_env(:p2p_docs, :causal_broadcast)[:ets_table] ||
                :causal_broadcast_state

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
      # Vector clock
      t: %{},
      # Delivery counters
      d: %{},
      # Pending messages
      buffer: MapSet.new(),
      # Where to send delivery notifications (added for the tests)
      delivery_pid: nil,
      # Delivery log
      delivery_log: []
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
    GenServer.call(server, {:remove_node, old_node})
  end

  def deliver_to_causal(server \\ __MODULE__, msg) do
    GenServer.cast(server, msg)
  end

  @doc """
  Initializes the CausalBroadcast server with the given options.
  The options should include `:my_id` (the ID of the current node) and `:nodes` (a list of known nodes).
  """
  # --> indicates that this function is an implementation of a callback defined in the GenServer behaviour more or less like @override in java
  @impl true
  def init(opts) do
    my_id = Keyword.fetch!(opts, :my_id)

    # Subscribe to neighbor events
    # get_peer_handler =
    #   Application.get_env(:p2p_docs, :neighbor_handler)[:module] ||
    #     P2PDocs.Network.NeighborHandler

    # :ok = get_peer_handler.subscribe(self())
    # Initialize the state with the given options
    # Try to fetch the state from ETS
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
          initial_state = %State{
            my_id: my_id,
            t: VectorClock.new(my_id),
            d: VectorClock.new(),
            buffer: MapSet.new(),
            delivery_pid: Keyword.get(opts, :delivery_pid, self()),
            delivery_log: []
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

  # Handle info messages from the neighbor handler part

  # @doc """
  # Handles incoming messages from the neighbor handler.
  # This includes messages about discovered and expired peers.
  # """
  # @impl true
  # def handle_info({:peer_discovered, %{name: node_name} = peer}, state) do
  #   Logger.info("Peer discovered: #{inspect(peer)}")
  #   new_node = String.to_existing_atom(node_name)
  #   GenServer.cast(__MODULE__, {:add_node, new_node})
  #   {:noreply, state}
  # end

  # @impl true
  # def handle_info({:peer_expired, %{name: node_name} = peer}, state) do
  #   Logger.info("Peer expired: #{inspect(peer)}")
  #   old_node = String.to_existing_atom(node_name)
  #   GenServer.cast(__MODULE__, {:remove_node, old_node})
  #   {:noreply, state}
  # end

  # Handle cast messages for broadcasting and receiving messages

  @doc """
  Handles the main logic of the causal broadcast protocol.
  This includes broadcasting messages, receiving messages, managing the state of the vector clocks and adding and removing nodes.
  """
  @impl true
  def handle_cast({:broadcast, msg}, state) do
    new_t = VectorClock.increment(state.t, state.my_id)
    Logger.debug("[#{node()}] BROADCASTING #{inspect(msg)} with VC: #{inspect(new_t)}")
    msg = {:message, msg, state.my_id, new_t}
    EchoWave.start_echo_wave(new_t, msg)
    # Update the ETS table with the new state
    :ets.insert(@table_name, {state.my_id, %{state | t: new_t}})
    {:noreply, %{state | t: new_t}}
  end

  @impl true
  def handle_cast({:message, msg, id, t_prime}, state) do
    Logger.debug(
      "[#{node()}] RECEIVED #{inspect(msg)} from #{inspect(id)} with VC: #{inspect(t_prime)}"
    )

    new_t = VectorClock.merge(state.t, t_prime)
    new_buffer = MapSet.put(state.buffer, {msg, id, t_prime})

    {delivered, remaining_buffer, new_d} = attempt_deliveries(new_buffer, state.d, id, [])

    for {delivered_msg, delivered_id, delivered_t} <- delivered do
      handle_delivery(msg)

      Logger.info(
        "[#{node()}] DELIVERED #{inspect(delivered_msg)} from #{inspect(delivered_id)} with VC: #{inspect(delivered_t)}"
      )
    end

    # Update the ETS table with the new state
    :ets.insert(
      @table_name,
      {state.my_id, %{state | t: new_t, d: new_d, buffer: remaining_buffer}}
    )
    :ets.insert(
      @table_name,
      {state.my_id, %{state | t: new_t, d: new_d, buffer: remaining_buffer}}
    )

    {:noreply,
     %{
       state
       | t: new_t,
         d: new_d,
         buffer: remaining_buffer,
         delivery_log: state.delivery_log ++ delivered
     }}
  end

  # @impl true
  # def handle_cast({:add_node, new_node}, state) do
  #   if new_node in state.nodes do
  #     # Already exists
  #     {:noreply, state}
  #   else
  #     # Initialize clocks for new node WITHOUT incrementing
  #     new_t = VectorClock.merge(state.t, VectorClock.new(new_node))
  #     new_d = VectorClock.merge(state.d, VectorClock.new(new_node))

  #     # Update the ETS table with the new state
  #     :ets.insert(
  #       @table_name,
  #       {state.my_id, %{state | nodes: [new_node | state.nodes], t: new_t, d: new_d}}
  #     )

  #     {:noreply, %{state | nodes: [new_node | state.nodes], t: new_t, d: new_d}}
  #   end
  # end

  # Handle removal of nodes,
  @impl true
  def handle_cast({:remove_node, old_node}, state) do
    if old_node in state.nodes do
      :ets.insert(
        @table_name,
        {state.my_id, %{state | nodes: List.delete(state.nodes, old_node)}}
      )

      {:noreply,
       %{
         state
         | nodes: List.delete(state.nodes, old_node)
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
    [{_key, saved_state}] = :ets.lookup(@table_name, state.my_id)
    {:reply, saved_state, state}
    [{_key, saved_state}] = :ets.lookup(@table_name, state.my_id)
    {:reply, saved_state, state}
  end

  @impl true
  def handle_call(:crash, _from, _state) do
    raise "simulated crash"
  end

  # Private helper functions
  # @doc """
  # Attempts to deliver messages from the buffer based on the causal delivery conditions.
  # This function checks if the messages in the buffer can be delivered based on the vector clocks and the current state.

  # """
  # TODO: Check if this is correct, should be, like in the slides, but idk
  defp attempt_deliveries(buffer, d, my_id, delivered) do
    # For each message in the buffer, check if it can be delivered
    deliverable =
      Enum.find(buffer, fn {_msg, sender_id, t_prime} -> deliverable?(t_prime, sender_id, d) end)

    case deliverable do
      nil ->
        {delivered, buffer, d}

      {_msg, sender_id, _t_prime} = found ->
        new_d = VectorClock.increment(d, sender_id)
        attempt_deliveries(MapSet.delete(buffer, found), new_d, my_id, [found | delivered])

      _ ->
        Logger.info("ERROR: invalid element in buffer!")
        {delivered, buffer, d}
    end
  end

  # @doc """
  # Checks if a message can be delivered based on the causal delivery conditions.
  # This function checks if the message's vector clock is less than or equal to the current vector clock and the delivery counter.
  # """
  # TODO: Check if this is correct, same as above
  defp deliverable?(t_prime, sender_id, d) do
    # Check if t_prime <= d' = d[sender_id] + 1
    d_prime = VectorClock.increment(d, sender_id)

    VectorClock.before?(t_prime, d_prime) or VectorClock.equal?(t_prime, d_prime)
  end

  # @doc """
  # Handles the actual delivery of a message.
  # """
  defp handle_delivery(msg) do
    # Placeholder for actual delivery logic
    Logger.info("Delivering message: #{inspect(msg)}")

    P2PDocs.CRDT.Manager.receive(msg)
  end
end
