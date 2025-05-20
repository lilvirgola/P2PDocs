defmodule P2PDocs.PubSub do
  use GenServer

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, MapSet.new(), name: __MODULE__)
  end

  def subscribe(pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  def unsubscribe(pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:unsubscribe, pid})
  end

  def broadcast(msg) do
    GenServer.cast(__MODULE__, {:broadcast, msg})
  end

  def broadcast_init() do
    GenServer.cast(__MODULE__, {:broadcast_init})
  end

  # Server Callbacks

  def init(state) do
    {:ok, state}
  end

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

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, MapSet.delete(state, pid)}
  end
end
