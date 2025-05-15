defmodule P2PDocs.ShutdownCatcher do
  use GenServer
  require Logger
  @moduledoc """
  This module is responsible for catching the shutdown signal
  and performing any necessary cleanup before the application
  terminates. It is a GenServer that traps exit signals and
  logs the reason for termination. It also stops the application
  """

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  def terminate(reason, _state) do
    Logger.debug("Application is shutting down! Reason: #{inspect(reason)}")
    :init.stop(:normal)
    :ok
  end
end
