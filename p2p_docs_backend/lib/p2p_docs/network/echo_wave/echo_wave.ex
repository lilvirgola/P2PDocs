defmodule P2PDocs.Network.EchoWave do
  use GenServer
  require Logger
  alias P2PDocs.Network.CausalBroadcast
  alias P2PDocs.Network.ReliableTransport

  @moduledoc """
  This module implements the Echo-Wave algorithm for peer-to-peer communication.
  It allows nodes to send messages to their neighbors and receive responses.
  The Echo-Wave algorithm is a simple and efficient way to propagate messages in a network.
  """

  defstruct id: nil,
            neighbors: [],
            pending_waves: %{}

  defmodule Wave do
    defstruct parent: nil,
              remaining: [],
              count: 0
  end

  def start_link({id, neighbors}, name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, {id, neighbors}, name: name)
  end

  def start_echo_wave(wave_id, msg) do
    GenServer.cast(__MODULE__, {:start_echo, wave_id, msg})
  end

  def add_neighbors(neighbors) do
    GenServer.cast(__MODULE__, {:add, neighbors})
  end

  def del_neighbors(neighbors) do
    GenServer.cast(__MODULE__, {:del, neighbors})
  end

  def update_neighbors(neighbors) do
    GenServer.cast(__MODULE__, {:update, neighbors})
  end

  def get_peer(id), do: id

  def init({id, neighbors}) do
    Logger.debug("Starting EchoWave module for node #{inspect(id)}")
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      id: id,
      neighbors: neighbors
    }

    {:ok, state}
  end

  def handle_cast({:start_echo, wave_id, msg}, state) do
    Logger.debug("#{state.id} started Echo-Wave #{inspect(wave_id)}")

    GenServer.cast(__MODULE__, {:token, self(), wave_id, 0, msg})

    {:noreply, state}
  end

  def handle_cast({:token, from, wave_id, count, msg}, state) do
    new_state =
      case Map.pop(state.pending_waves, wave_id) do
        {nil, pending} ->
          handle_new_wave(state, from, wave_id, count, msg, pending)

        {prev = %Wave{}, pending} ->
          handle_existing_wave(state, from, wave_id, count, prev, pending)
      end

    new_state =
      if report_back?(new_state, wave_id) do
        Logger.debug("#{state.id} removes #{inspect(wave_id)} from its pending waves")

        %__MODULE__{
          new_state
          | pending_waves: Map.delete(new_state.pending_waves, wave_id)
        }
      else
        new_state
      end

    {:noreply, new_state}
  end

  def handle_cast({:update, neighbors}, state), do: {:noreply, %{state | neighbors: neighbors}}

  def handle_cast({:add, neighbors}, state),
    do: {:noreply, %{state | neighbors: state.neighbors ++ neighbors}}

  def handle_cast({:del, neighbors}, state),
    do: {:noreply, %{state | neighbors: state.neighbors -- neighbors}}

  def handle_cast({:wave_complete, _from, wave_id, count}, state) do
    Logger.debug("Echo-Wave #{inspect(wave_id)} ended with #{count} nodes")
    {:noreply, state}
  end

  def handle_cast(_, state) do
    Logger.error("Message not valid!")
    {:noreply, state}
  end

  # def terminate(reason, state) do
  #   Logger.debug(
  #     "Terminating EchoWave process for node #{inspect(state)} due to #{inspect(reason)}"
  #   )

  #   # placeholder for any cleanup tasks
  #   :ok
  # end

  defp send_token(state, neighbor, wave_id, msg) do
    reliable_transport().send(
      state.id,
      get_peer(neighbor),
      __MODULE__,
      {:token, state.id, wave_id, 0, msg}
    )
  end

  defp reliable_transport() do
    Application.get_env(:p2p_docs, :reliable_transport, ReliableTransport)
  end

  defp report_back?(state, wave_id) do
    case Map.get(state.pending_waves, wave_id) do
      %Wave{parent: parent, remaining: [], count: count} ->
        Logger.debug("#{state.id} reports back to #{inspect(parent)} with #{count} children")
        send_back(state, parent, wave_id, count)
        true

      _ ->
        false
    end
  end

  defp send_back(state, parent, wave_id, count) when is_pid(parent) do
    send(parent, {:wave_complete, state.id, wave_id, count})
  end

  defp send_back(state, parent, wave_id, count) do
    reliable_transport().send(
      state.id,
      get_peer(parent),
      __MODULE__,
      {:token, state.id, wave_id, count, nil}
    )
  end

  defp handle_new_wave(state, from, wave_id, count, msg, pending) do
    Logger.debug(
      "#{state.id} received #{inspect(wave_id)} token for the first time, from #{inspect(from)}"
    )

    causal_broadcast().deliver_to_causal(causal_broadcast(), msg)
    children = state.neighbors -- [from]
    Enum.each(children, &send_token(state, &1, wave_id, msg))

    wave = %Wave{parent: from, remaining: children, count: count + 1}
    %{state | pending_waves: Map.put(pending, wave_id, wave)}
  end

  defp causal_broadcast() do
    Application.get_env(:p2p_docs, :causal_broadcast, CausalBroadcast)[:module]
  end

  defp handle_existing_wave(state, from, wave_id, count, prev, pending) do
    Logger.debug("#{state.id} received #{inspect(wave_id)} token from #{inspect(from)}")

    updated = %{prev | remaining: prev.remaining -- [from], count: prev.count + count}
    %{state | pending_waves: Map.put(pending, wave_id, updated)}
  end
end
