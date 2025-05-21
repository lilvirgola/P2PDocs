defmodule P2PDocs.Network.EchoWave do
  @moduledoc """
  This module implements the Echo-Wave algorithm for peer-to-peer communication.
  It allows nodes to send messages to their neighbors and receive responses.
  The Echo-Wave algorithm is a simple and efficient way to propagate messages in a network.

  State of the EchoWave server.

  - `id`: Unique identifier of the node.
  - `neighbors`: List of neighbor node identifiers.
  - `pending_waves`: Map tracking ongoing waves by their `wave_id`.
  """

  use GenServer
  require Logger
  alias P2PDocs.Network.CausalBroadcast
  alias P2PDocs.Network.ReliableTransport

  @table_name Application.compile_env(:p2p_docs, :echo_wave)[:ets_table] ||
                :echo_wave_state

  @typedoc """
  State of the EchoWave server.

  - `id`: Unique identifier of the node.
  - `neighbors`: List of neighbor node identifiers.
  - `pending_waves`: Map tracking ongoing waves by their `wave_id`.
  """
  defstruct id: nil,
            neighbors: [],
            pending_waves: %{}

  defmodule Wave do
    @moduledoc """
    Represents an ongoing Echo-Wave propagation wave.

    - `parent`: PID or identifier of the node that forwarded the wave.
    - `remaining`: List of neighbor nodes yet to be visited.
    - `count`: Accumulated number of nodes that have processed the wave.
    """

    defstruct parent: nil,
              remaining: [],
              count: 0
  end

  ## Public API

  @doc """
  Starts the EchoWave GenServer.

  ## Parameters
  - `{id, neighbors}`: Tuple where `id` is this node's identifier, and `neighbors` is a list of neighbor node IDs.
  - `name` (optional): Registered name for the GenServer (defaults to module name).

  ## Returns
  - `{:ok, pid}` on success.
  """
  def start_link({id, neighbors}, name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, {id, neighbors}, name: name)
  end

  @doc """
  Initiates an Echo-Wave with given `wave_id` and message `msg`.
  Sends a token to self to kick off propagation to neighbors.
  """
  def start_echo_wave(wave_id, msg) do
    GenServer.cast(__MODULE__, {:start_echo, wave_id, msg})
  end

  @doc """
  Adds the given `neighbors` to this node's neighbor list.
  """
  def add_neighbors(neighbors) do
    GenServer.cast(__MODULE__, {:add, neighbors})
  end

  @doc """
  Removes the given `neighbors` from this node's neighbor list.
  """
  def del_neighbors(neighbors) do
    GenServer.cast(__MODULE__, {:del, neighbors})
  end

  @doc """
  Replaces this node's neighbor list with `neighbors`.
  """
  def update_neighbors(neighbors) do
    GenServer.cast(__MODULE__, {:update, neighbors})
  end

  @doc """
  Retrieves the peer identifier for the given `id`.

  Currently returns the same `id`, but can be adapted for name resolution.
  """
  def get_peer(id), do: id

  ## GenServer Callbacks

  # Initializes the GenServer state.
  #
  # - Sets process to trap exits.
  # - Logs startup with node `id`.
  @impl true
  def init({id, neighbors}) do
    Logger.debug("Starting EchoWave module for node #{inspect(id)}")
    Process.flag(:trap_exit, true)

    try do
      case :ets.lookup(@table_name, id) do
        [{_key, state}] ->
          # State found in ETS, return it
          Logger.debug("State found in ETS: #{inspect(state)}")
          # restore the state from ETS
          {:ok, state}

        [] ->
          Logger.debug("No state found in ETS, creating new state")
          # No state found in ETS, create new state
          initial_state = %__MODULE__{
            id: id,
            neighbors: neighbors
          }

          # Store the initial state in the ETS table
          :ets.insert(@table_name, {id, initial_state})
          {:ok, initial_state}
      end
    catch
      :error, :badarg ->
        Logger.error("ETS table not found")
        {:stop, :badarg}
    end
  end

  @impl true
  def handle_cast({:start_echo, wave_id, msg}, state) do
    Logger.debug("#{state.id} started Echo-Wave #{inspect(wave_id)}")
    GenServer.cast(__MODULE__, {:token, self(), wave_id, 0, msg})
    {:noreply, state}
  end

  # Main token handler: distinguishes new vs existing waves,
  # updates state, and triggers report-back when complete.
  @impl true
  def handle_cast({:token, from, wave_id, count, msg}, state) do
    {old, pending} = Map.pop(state.pending_waves, wave_id)

    new_state =
      case old do
        nil ->
          handle_new_wave(state, from, wave_id, count, msg, pending)

        prev = %Wave{} ->
          handle_existing_wave(state, from, wave_id, count, prev, pending)
      end

    # Clean up if this wave is finished
    new_state =
      if report_back?(new_state, wave_id) do
        Logger.debug("#{state.id} removes #{inspect(wave_id)} from pending_waves")
        %{new_state | pending_waves: Map.delete(new_state.pending_waves, wave_id)}
      else
        new_state
      end

    :ets.insert(@table_name, {state.id, new_state})
    {:noreply, new_state}
  end

  # Replaces neighbors list with the provided `neighbors`.
  @impl true
  @doc """
  Replaces neighbors list with the provided `neighbors`.
  """
  def handle_cast({:update, neighbors}, state) do
    new_state = %{state | neighbors: neighbors}
    :ets.insert(@table_name, {state.id, new_state})
    {:noreply, new_state}
  end

  @impl true
  @doc """
  Appends the provided `neighbors` to the existing list.
  """
  def handle_cast({:add, neighbors}, state) do
    new_state = %{state | neighbors: state.neighbors ++ neighbors}
    :ets.insert(@table_name, {state.id, new_state})
    {:noreply, new_state}
  end

  # Removes the provided `neighbors` from the existing list.
  @impl true
  @doc """
  Removes the provided `neighbors` from the existing list.
  """
  def handle_cast({:del, neighbors}, state) do
    new_state = %{state | neighbors: state.neighbors -- neighbors}
    :ets.insert(@table_name, {state.id, new_state})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:wave_complete, _from, wave_id, count}, state) do
    Logger.debug("Echo-Wave #{inspect(wave_id)} ended with #{count} nodes")
    {:noreply, state}
  end

  # Catches any unrecognized cast messages and logs an error.
  @impl true
  def handle_cast(_, state) do
    Logger.error("Message not valid!")
    {:noreply, state}
  end

  ## Private Helper Functions

  @doc false
  defp send_token(from, neighbor, wave_id, msg) do
    reliable_transport().send(
      from,
      get_peer(neighbor),
      __MODULE__,
      {:token, from, wave_id, 0, msg}
    )
  end

  @doc false
  defp reliable_transport() do
    Application.get_env(:p2p_docs, :reliable_transport, ReliableTransport)[:module]
  end

  @doc false
  defp causal_broadcast() do
    Application.get_env(:p2p_docs, :causal_broadcast, CausalBroadcast)[:module]
  end

  @doc false
  defp report_back?(state, wave_id) do
    case Map.get(state.pending_waves, wave_id) do
      %Wave{parent: parent, remaining: [], count: count} ->
        Logger.debug("#{state.id} reports back to #{inspect(parent)} with #{count} children")
        send_back(state.id, parent, wave_id, count)
        true

      _ ->
        false
    end
  end

  @doc false
  defp send_back(from, parent, wave_id, count) when is_pid(parent) do
    GenServer.cast(parent, {:wave_complete, from, wave_id, count})
  end

  @doc false
  defp send_back(from, parent, wave_id, count) do
    reliable_transport().send(
      from,
      get_peer(parent),
      __MODULE__,
      {:token, from, wave_id, count, nil}
    )
  end

  @doc false
  defp handle_new_wave(state, from, wave_id, count, msg, pending) do
    Logger.debug(
      "#{state.id} received #{inspect(wave_id)} token for the first time, from #{inspect(from)}"
    )

    causal_broadcast().deliver_to_causal(causal_broadcast(), msg)

    children = state.neighbors -- [from]
    Enum.each(children, &send_token(state.id, &1, wave_id, msg))

    wave = %Wave{parent: from, remaining: children, count: count + 1}
    new_state = %{state | pending_waves: Map.put(pending, wave_id, wave)}
    :ets.insert(@table_name, {state.id, new_state})
    new_state
  end

  @doc false
  defp handle_existing_wave(state, from, wave_id, count, prev, pending) do
    Logger.debug("#{state.id} received #{inspect(wave_id)} token from #{inspect(from)}")
    updated = %{prev | remaining: prev.remaining -- [from], count: prev.count + count}
    new_state = %{state | pending_waves: Map.put(pending, wave_id, updated)}
    :ets.insert(@table_name, {state.id, new_state})
    new_state
  end
end
