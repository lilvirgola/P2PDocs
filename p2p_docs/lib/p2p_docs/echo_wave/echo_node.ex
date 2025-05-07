defmodule EchoWave.EchoNode do
  use GenServer

  defstruct id: nil,
            neighbors: nil,
            parent: nil,
            to_be_received: nil,
            count: 0

  def start_link({id, neighbors}) do
    GenServer.start_link(__MODULE__, {id, neighbors}, name: get_peer(id))
  end

  # def get_peer(id), do: {:via, Registry, {:echo_registry, id}}
  def get_peer(id), do: id

  def init({id, neighbors}) do
    state = %__MODULE__{
      id: id,
      neighbors: neighbors,
      to_be_received: neighbors
    }

    {:ok, state}
  end

  def handle_cast({:token, from, count, msg}, %__MODULE__{parent: nil} = state) do
    IO.puts("Node #{state.id} received token for the first time, from #{inspect(from)}")

    neighbors_except_parent = state.neighbors -- [from]

    Enum.each(neighbors_except_parent, fn neighbor ->
      GenServer.cast(get_peer(neighbor), {:token, state.id, 0, msg})
    end)

    new_state = %__MODULE__{
      state
      | parent: from,
        to_be_received: neighbors_except_parent,
        count: count + 1
    }

    {:noreply, new_state}
  end

  def handle_cast({:token, from, count, msg}, state) do
    IO.puts("Node #{state.id} received token from #{inspect(from)}")

    new_to_be_received = state.to_be_received -- [from]

    new_state = %__MODULE__{
      state
      | to_be_received: new_to_be_received,
        count: state.count + count
    }

    if Enum.empty?(new_to_be_received) do
      IO.puts(
        "Node #{state.id} reports token back to #{inspect(state.parent)} with #{new_state.count} children"
      )

      if is_pid(state.parent) do
        send(state.parent, {:tree_complete, state.id, new_state.count, msg})
      else
        GenServer.cast(get_peer(state.parent), {:token, state.id, new_state.count, msg})
      end
    end

    {:noreply, new_state}
  end
end
