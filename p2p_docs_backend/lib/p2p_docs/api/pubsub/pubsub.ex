defmodule P2PDocs.PubSub do
  use GenServer

  @moduledoc """
  This module implements a simple PubSub system using GenServer.
  It allows processes to subscribe to receive messages and broadcast messages to all subscribers.
  We use it for comunicate with all the websocket clients.
  """

  # Client API
  @doc """
  Starts the PubSub server.
  It initializes the state as an empty MapSet.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, MapSet.new(), name: __MODULE__)
  end

  @doc """
  Subscribes a process to receive messages.
  The process ID (pid) is monitored, and when it terminates, it will be removed from the subscribers list.
  """
  def subscribe(pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  @doc """
  Unsubscribes a process from receiving messages.
  The process ID (pid) is removed from the subscribers list.
  """
  def unsubscribe(pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:unsubscribe, pid})
  end

  @doc """
  Broadcasts a message to all subscribed processes.
  The message is sent as a cast to all subscribers.
  """
  def broadcast(msg) do
    GenServer.cast(__MODULE__, {:broadcast, msg})
  end

  @doc """
  Broadcasts an initialization message to all subscribed processes.
  """
  def broadcast_init() do
    GenServer.cast(__MODULE__, {:broadcast_init})
  end

  # Server Callbacks
  @doc """
  Initializes the server state.
  """
  def init(state) do
    {:ok, state}
  end

  @doc """
  Handles incoming messages.
  It matches the message type and updates the state accordingly.
  """
  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    {:noreply, MapSet.put(state, pid)}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, MapSet.delete(state, pid)}
  end

  def handle_cast({:broadcast, msg}, state) do
    Enum.each(state, fn pid ->
      send(pid, {:send, Jason.encode!(msg)})
    end)

    {:noreply, state}
  end

  def handle_cast({:broadcast_init}, state) do
    Enum.each(state, fn pid ->
      send(pid, {:send_init})
    end)

    {:noreply, state}
  end

  @doc """
  Handles the termination of a monitored process.
  When a process terminates, it is removed from the subscribers list.
  """
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, MapSet.delete(state, pid)}
  end
end
