defmodule P2PDocs.Network.CausalBroadcast do
  use GenServer

  # this can be replaced with a more efficient implementation later
  alias P2PDocs.Network.NaiveVectorClock, as: VectorClock
  require Logger
  import P2PDocs.Utils.Callbacks

  @table_name Application.compile_env(:p2p_docs, :causal_broadcast)[:ets_table] ||
                :causal_broadcast_state

  @moduledoc """
  This module implements our causal broadcast protocol using vector clocks.
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
  @callback broadcast(msg :: any) :: :ok
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

  @callback deliver_to_causal(server :: any, msg :: any) :: {:ok}
  def deliver_to_causal(server \\ __MODULE__, msg) do
    GenServer.cast(server, msg)
  end

  def get_vc_and_d_state() do
    GenServer.call(__MODULE__, {:get_vc_and_d})
  end

  @doc """
  Initializes the CausalBroadcast server with the given options.
  The options should include `:my_id` (the ID of the current node) and `:nodes` (a list of known nodes).
  """
  # --> indicates that this function is an implementation of a callback defined in the GenServer behaviour more or less like @override in java
  @impl true
  def init(opts) do
    Logger.debug("Starting CausalBroadcast module for node #{inspect(opts[:my_id])}")
    Process.flag(:trap_exit, true)
    my_id = Keyword.fetch!(opts, :my_id)

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
          initial_state = %__MODULE__{
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
    echo_wave().start_echo_wave(new_t, msg)
    # Update the ETS table with the new state
    :ets.insert(@table_name, {state.my_id, %{state | t: new_t}})
    {:noreply, %{state | t: new_t}}
  end

  @impl true
  def handle_cast({:upd_vc_and_d, {vc, d}}, state) do
    Logger.debug("Node #{inspect(state.my_id)} is updating its state!")

    new_state = %{
      state
      | t: vc,
        d: d
    }

    # Store the updated state in ETS
    :ets.insert(@table_name, {state.my_id, new_state})
    {:noreply, new_state}
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

  def handle_cast(_, state) do
    Logger.error("Message not valid!")
    {:noreply, state}
  end

  @doc """
  Handles synchronous calls to get the state of the server.
  This includes the vector clock, delivery counters, and pending messages.
  """
  @impl true
  def handle_call(:get_state, _from, state) do
    [{_key, saved_state}] = :ets.lookup(@table_name, state.my_id)
    {:reply, saved_state, state}
  end

  @impl true
  def handle_call({:get_vc_and_d}, _from, state) do
    Logger.debug("Node #{inspect(state.my_id)} is sending its vector clock and d!")
    {:reply, {state.t, state.d}, state}
  end

  # Private helper functions
  # @doc """
  # Attempts to deliver messages from the buffer based on the causal delivery conditions.
  # This function checks if the messages in the buffer can be delivered based on the vector clocks and the current state.

  # """
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
        Logger.debug("ERROR: invalid element in buffer!")
        {delivered, buffer, d}
    end
  end

  # @doc """
  # Checks if a message can be delivered based on the causal delivery conditions.
  # This function checks if the message's vector clock is less than or equal to the current vector clock and the delivery counter.
  # """
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

    crdt_manager().receive_msg(msg)
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Terminating CausalBrodcast process for node #{state.my_id} due to #{inspect(reason)}"
    )

    # placeholder for any cleanup tasks
    :ok
  end
end
