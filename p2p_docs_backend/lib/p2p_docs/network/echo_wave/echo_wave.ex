defmodule P2PDocs.Network.EchoWave do
  use GenServer
  require Logger
  alias P2PDocs.Network

  @moduledoc """
  This module implements the Echo-Wave algorithm for peer-to-peer communication.
  It allows nodes to send messages to their neighbors and receive responses.
  The Echo-Wave algorithm is a simple and efficient way to propagate messages in a network.
  """

  defstruct id: nil,
            neighbors: [],
            pending_waves: %{}

  defmodule State do
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

  # def get_peer(id), do: {:via, Registry, {:echo_registry, id}}
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
      case state.pending_waves[wave_id] do
        nil ->
          Logger.debug(
            "#{state.id} received #{inspect(wave_id)} token for the first time, from #{inspect(from)}"
          )

          Network.CausalBroadcast.deliver_to_causal(msg)

          neighbors_except_parent = state.neighbors -- [from]

          Enum.each(neighbors_except_parent, fn neighbor ->
            GenServer.cast(
              {__MODULE__, get_peer(neighbor)},
              {:token, state.id, wave_id, 0, msg}
            )
          end)

          # %__MODULE__{
          #   state
          #   | parent: from,
          #     remaining: neighbors_except_parent,
          #     count: count + 1
          # }

          %__MODULE__{
            state
            | pending_waves:
                Map.put(state.pending_waves, wave_id, %State{
                  parent: from,
                  remaining: neighbors_except_parent,
                  count: count + 1
                })
          }

        _ ->
          Logger.debug("#{state.id} received #{inspect(wave_id)} token from #{inspect(from)}")

          new_remaining = state.pending_waves[wave_id].remaining -- [from]

          # %__MODULE__{
          #   state
          #   | remaining: new_remaining,
          #     count: state.count + count
          # }

          %__MODULE__{
            state
            | pending_waves:
                Map.update!(state.pending_waves, wave_id, fn prev_state ->
                  %State{
                    prev_state
                    | remaining: new_remaining,
                      count: prev_state.count + count
                  }
                end)
          }
      end

    new_state =
      if report_back?(new_state, wave_id, msg) do
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

  # def handle_cast({:token, from, count, msg}, state) do
  #   Logger.debug("Node #{state.id} received token from #{inspect(from)}")

  #   new_remaining = state.remaining -- [from]

  #   new_state = %__MODULE__{
  #     state
  #     | remaining: new_remaining,
  #       count: state.count + count
  #   }

  #   report_back?(new_state, msg)

  #   {:noreply, new_state}
  # end

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

  def handle_cast({:wave_complete, _, wave_id}, state) do
    Logger.debug("Echo-Wave #{inspect(wave_id)} ended")

    # new_state = %__MODULE__{state | pending_waves: Map.delete(state.pending_waves, wave_id)}

    new_state = state
    {:noreply, new_state}
  end

  defp report_back?(state, wave_id, msg) do
    if not Enum.empty?(state.pending_waves[wave_id].remaining) do
      false
    else
      Logger.debug(
        "#{state.id} reports token back to #{inspect(state.pending_waves[wave_id].parent)} with #{state.pending_waves[wave_id].count} children"
      )

      if is_pid(state.pending_waves[wave_id].parent) do
        GenServer.cast(
          state.pending_waves[wave_id].parent,
          {:wave_complete, state.id, wave_id}
        )
      else
        GenServer.cast(
          {__MODULE__, get_peer(state.pending_waves[wave_id].parent)},
          {:token, state.id, wave_id, state.pending_waves[wave_id].count, msg}
        )
      end

      true
    end
  end

  def terminate(reason, state) do
    Logger.debug("Terminating EchoWave process for node #{inspect(state)} due to #{inspect(reason)}")
    # placeholder for any cleanup tasks
    :ok
  end
end
