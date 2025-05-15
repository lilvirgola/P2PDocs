defmodule P2PDocs.Network.EchoWave do
  use GenServer
  require Logger
  alias P2PDocs.Network

  defstruct id: nil,
            neighbors: nil,
            parent: nil,
            remaining: nil,
            count: 0

  def start_link({id, neighbors}) do
    GenServer.start_link(__MODULE__, {id, neighbors}, name: get_peer(id))
  end

  def start_echo_wave(id, msg) do
    GenServer.cast(get_peer(id), {:token, self(), 0, msg})
  end

  def add_neighbors(id, neighbors) do
    GenServer.cast(get_peer(id), {:add, neighbors})
  end

  def del_neighbors(id, neighbors) do
    GenServer.cast(get_peer(id), {:del, neighbors})
  end


  def update_neighbors(id, neighbors) do
    GenServer.cast(get_peer(id), {:update, neighbors})
  end

  # def get_peer(id), do: {:via, Registry, {:echo_registry, id}}
  def get_peer(id), do: id

  def init({id, neighbors}) do
    state = %__MODULE__{
      id: id,
      neighbors: neighbors
    }

    {:ok, state}
  end

  def handle_cast({:token, from, count, msg}, %__MODULE__{parent: nil} = state) do
    Logger.debug("Node #{state.id} received token for the first time, from #{inspect(from)}")

    Network.CausalBroadcast.deliver_to_causal(msg)

    neighbors_except_parent = state.neighbors -- [from]

    Enum.each(neighbors_except_parent, fn neighbor ->
      GenServer.cast(get_peer(neighbor), {:token, {get_peer(state.id), state.id}, 0, msg})
    end)

    new_state = %__MODULE__{
      state
      | parent: from,
        remaining: neighbors_except_parent,
        count: count + 1
    }

    report_back?(new_state, msg)

    {:noreply, new_state}
  end

  def handle_cast({:token, from, count, msg}, state) do
    Logger.debug("Node #{state.id} received token from #{inspect(from)}")

    new_remaining = state.remaining -- [from]

    new_state = %__MODULE__{
      state
      | remaining: new_remaining,
        count: state.count + count
    }

    report_back?(new_state, msg)

    {:noreply, new_state}
  end

  def handle_cast({:update, neighbors}, state) do
    new_state = %__MODULE__{
      state
      | neighbors: neighbors
    }

    {:noreply, new_state}
  end

  def handle_cast({:add, neighbors}, state) do
    new_state = %__MODULE__{
      state
      | neighbors: state.neighbors ++ neighbors
    }

    {:noreply, new_state}
  end

  def handle_cast({:del, neighbors}, state) do
    new_state = %__MODULE__{
      state
      | neighbors: state.neighbors -- neighbors
    }

    {:noreply, new_state}
  end

  # def handle_call(:get_state, _from, state) do
  #   {:reply, state, state}
  # end

  defp report_back?(state, msg) do
    if Enum.empty?(state.remaining) do
      Logger.debug(
        "Node #{state.id} reports token back to #{inspect(state.parent)} with #{state.count} children"
      )

      if is_pid(state.parent) do
        send(state.parent, {:tree_complete, state.id, state.count, msg})
      else
        GenServer.cast(
          get_peer(state.parent),
          {:token, {get_peer(state.id), state.id}, state.count, msg}
        )
      end
    end
  end
end
