defmodule P2PDocs.Network.ReliableTransport do
  use GenServer
  require Logger

  # milliseconds
  @retry_interval 5_000

  defstruct node_id: nil,
            # %{msg_id => %{from, to, module, payload, timer_ref}}
            pending_ack: %{},
            past_msg: MapSet.new()

  ## API

  @doc """
  Sends `payload` from `from` to `to` under the given module,
  and retries every #{@retry_interval}ms until an ACK is received.
  """
  def send(from, to, module, payload) do
    GenServer.cast(__MODULE__, {:send, from, to, module, payload})
  end

  ## GenServer callbacks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.debug("Starting #{__MODULE__} module for node #{inspect(opts[:node_id])}")
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      node_id: Keyword.fetch!(opts, :node_id),
      pending_ack: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:send, from, to, module, payload}, state) do
    # generate a unique message id
    msg_id = {state.node_id, :erlang.unique_integer([:monotonic, :positive])}
    Logger.debug("Sending msg_id=#{msg_id} to #{inspect(to)}: #{inspect({module, payload})}")

    # actually send it
    GenServer.cast({__MODULE__, to}, {:deliver, from, module, payload, msg_id})

    # schedule retry
    timer_ref = Process.send_after(self(), {:timeout, msg_id}, @retry_interval)

    # record in pending_ack
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
  def handle_cast({:deliver, from, module, payload, msg_id}, state) do
    unless MapSet.member?(state.past_msg, msg_id) do
      Logger.debug(
        "Received msg_id=#{msg_id} from #{inspect(from)}: #{inspect({module, payload})}"
      )

      # forward to the actual handler
      GenServer.cast({module, state.node_id}, payload)

      # send back ACK to origin
      GenServer.cast({__MODULE__, from}, {:ack, msg_id})
      {:noreply, %__MODULE__{state | past_msg: MapSet.put(state.past_msg, msg_id)}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:ack, msg_id}, state) do
    case Map.pop(state.pending_ack, msg_id) do
      {nil, _} ->
        # already removed or unknown
        {:noreply, state}

      {%{timer_ref: timer_ref} = _info, new_pending} ->
        Logger.debug("ACK received for msg_id=#{msg_id}, cancelling retries")
        Process.cancel_timer(timer_ref)
        {:noreply, %{state | pending_ack: new_pending}}
    end
  end

  def handle_cast(_, state) do
    Logger.error("Message not valid!")
    {:noreply, state}
  end

  @impl true
  def handle_info({:timeout, msg_id}, state) do
    case Map.get(state.pending_ack, msg_id) do
      nil ->
        # either already ACKed or never existed
        {:noreply, state}

      %{from: from, to: to, module: module, payload: payload} = info ->
        Logger.warning("Retrying msg_id=#{msg_id} to #{inspect(to)}")

        # retransmit
        GenServer.cast({__MODULE__, to}, {:deliver, from, module, payload, msg_id})

        # schedule next retry
        new_timer = Process.send_after(self(), {:timeout, msg_id}, @retry_interval)

        # update stored timer_ref
        new_pending = Map.put(state.pending_ack, msg_id, %{info | timer_ref: new_timer})
        {:noreply, %{state | pending_ack: new_pending}}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Terminating #{__MODULE__} process for node #{inspect(state)} due to #{inspect(reason)}"
    )

    # placeholder for any cleanup tasks
    :ok
  end
end
