defmodule P2PDocs.Network.ReliableTransport do
  @moduledoc """
  A transport layer that ensures reliable message delivery between nodes.

  Messages are sent via GenServer casts and retried every @retry_interval milliseconds
  until an acknowledgement (ACK) is received. Duplicate deliveries are filtered.

  State of the ReliableTransport server.

  - `node_id`: Identifier of this node.
  - `pending_ack`: Map of `msg_id` to metadata (`from`, `to`, `module`, `payload`, `timer_ref`) for messages awaiting ACK.
  - `past_msg`: Set of `msg_id` values already delivered, to suppress duplicates.
  """

  use GenServer
  require Logger

  @retry_interval 5_000

  @type node_id            :: String.t()
  @type module_name        :: module()
  @type payload            :: any()
  @type msg_id             :: {node_id(), pos_integer()}
  @type timer_ref          :: reference()

  @type pending_ack_entry  :: %{
                              from: node_id(),
                              to: node_id(),
                              module: module_name(),
                              payload: payload(),
                              timer_ref: timer_ref()
                            }
  @type pending_ack        :: %{msg_id() => pending_ack_entry()}
  @type past_msg           :: MapSet.t(msg_id())

  @type t                  :: %__MODULE__{
                              node_id: node_id(),
                              pending_ack: pending_ack(),
                              past_msg: past_msg()
                            }

  defstruct node_id: nil,
            pending_ack: %{},
            past_msg: MapSet.new()

  ## Public API

  @doc """
  Sends the given `payload` from `from` to `to` under the specified `module`,
  retrying every #{@retry_interval}ms until an ACK is received.
  """
  @callback send(from :: any, to :: any, module :: any, payload :: any) :: :ok
  @spec send(from :: node_id(), to :: node_id(), module :: module_name(), payload :: payload()) :: :ok
  def send(from, to, module, payload) do
    GenServer.cast(__MODULE__, {:send, from, to, module, payload})
  end

  ## GenServer Startup

  @doc """
  Starts the ReliableTransport GenServer.

  ## Options
  - `:node_id` (required) – identifier for this node.

  ## Returns
  - `{:ok, pid}` on success.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  @doc """
  Initializes the transport state.

  Sets up the node identifier and empty pending/duplicate tracking.
  """
  def init(opts) do
    Logger.debug("Starting #{__MODULE__} for node #{inspect(opts[:node_id])}")
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      node_id: Keyword.fetch!(opts, :node_id),
      pending_ack: %{},
      past_msg: MapSet.new()
    }

    {:ok, state}
  end

  ## Delivery and Retry Callbacks

  @impl true
  # Handles the initial send request:
  #
  # - Generates a unique `msg_id`.
  # - Casts a `:deliver` message to the target transport.
  # - Schedules a retry via `Process.send_after/3`.
  # - Stores metadata in `pending_ack`.
  def handle_cast({:send, from, to, module, payload}, state) do
    msg_id = {state.node_id, :erlang.unique_integer([:monotonic, :positive])}

    Logger.debug(
      "Sending msg_id=#{inspect(msg_id)} to #{inspect(to)}: #{inspect({module, payload})}"
    )

    GenServer.cast({__MODULE__, to}, {:deliver, from, module, payload, msg_id})

    timer_ref = Process.send_after(self(), {:timeout, msg_id}, @retry_interval)

    pending_ack =
      Map.put(state.pending_ack, msg_id, %{
        from: from,
        to: to,
        module: module,
        payload: payload,
        timer_ref: timer_ref
      })

    {:noreply, %{state | pending_ack: pending_ack}}
  end

  @impl true
  # Handles incoming deliveries:
  #
  # - If `msg_id` not seen before, forwards payload to the target module and sends ACK back.
  # - If duplicate, immediately sends ACK without re-delivering the payload.
  def handle_cast({:deliver, from, module, payload, msg_id}, state) do
    if MapSet.member?(state.past_msg, msg_id) do
      GenServer.cast({__MODULE__, from}, {:ack, msg_id})
      {:noreply, state}
    else
      Logger.debug(
        "Received msg_id=#{inspect(msg_id)} from #{inspect(from)}: #{inspect({module, payload})}"
      )

      GenServer.cast({module, state.node_id}, payload)
      GenServer.cast({__MODULE__, from}, {:ack, msg_id})

      new_past = MapSet.put(state.past_msg, msg_id)
      {:noreply, %{state | past_msg: new_past}}
    end
  end

  @impl true
  # Handles ACKs:
  #
  # - Cancels the retry timer for the acknowledged `msg_id`.
  # - Removes it from `pending_ack`.
  def handle_cast({:ack, msg_id}, state) do
    case Map.pop(state.pending_ack, msg_id) do
      {nil, _} ->
        {:noreply, state}

      {%{timer_ref: timer_ref}, new_pending} ->
        Logger.debug("ACK received for msg_id=#{inspect(msg_id)}, cancelling retries")
        Process.cancel_timer(timer_ref)
        {:noreply, %{state | pending_ack: new_pending}}
    end
  end

  @impl true

  # Catches unrecognized cast messages and logs an error.
  def handle_cast(_, state) do
    Logger.error("Message not valid!")
    {:noreply, state}
  end

  @impl true
  # Handles retry timeouts:
  #
  # - If `msg_id` still pending, logs a warning and retransmits.
  # - Reschedules the next timeout.
  def handle_info({:timeout, msg_id}, state) do
    case Map.get(state.pending_ack, msg_id) do
      nil ->
        {:noreply, state}

      %{from: from, to: to, module: module, payload: payload} = info ->
        Logger.warning("Retrying msg_id=#{inspect(msg_id)} to #{inspect(to)}")
        GenServer.cast({__MODULE__, to}, {:deliver, from, module, payload, msg_id})

        new_timer = Process.send_after(self(), {:timeout, msg_id}, @retry_interval)
        new_pending = Map.put(state.pending_ack, msg_id, %{info | timer_ref: new_timer})
        {:noreply, %{state | pending_ack: new_pending}}
    end
  end

  @impl true
  # Called when the GenServer is terminating.
  #
  # Logs the termination reason; placeholder for cleanup.
  def terminate(reason, state) do
    Logger.debug("Terminating #{__MODULE__} for node #{inspect(state)} due to #{inspect(reason)}")
    :ok
  end
end
