defmodule P2PDocs.Application do
  @moduledoc """
  The main application module for the P2PDocs application.
  This module is responsible for starting the application and its supervision tree.
  It includes the API server and any other necessary components.
  """
  require Logger

  use Application

  @cookie Application.compile_env(:p2p_docs, :neighbor_handler)[:cookie] ||
            :default
  @ets_causal_broadcast Application.compile_env(:p2p_docs, :causal_broadcast)[:ets_table] ||
                          :causal_broadcast_state
  @ets_crdt_manager Application.compile_env(:p2p_docs, :crdt_manager)[:ets_table] ||
                      :crdt_manager_state
  @ets_neighbor_handler Application.compile_env(:p2p_docs, :neighbor_handler)[:ets_table] ||
                          :neighbor_handler_state
  @ets_echo_wave Application.compile_env(:p2p_docs, :echo_wave)[:ets_table] ||
                   :echo_wave_state
  @ets_reliable_transport Application.compile_env(:p2p_docs, :reliable_transport)[:ets_table] ||
                            :reliable_transport_state

  @doc """
  This module is responsible for starting the P2PDocs application.
  It initializes the necessary components and sets up the supervision tree.
  It also handles the ETS tables for storing the state of the application.
  """
  @impl true
  def start(_type, _args) do
    Logger.info("Starting P2PDocs application...")
    # If the environment is not test, set the cookie for the node
    # This is important for distributed Erlang communication
    if Mix.env() != :test do
      Node.set_cookie(node(), @cookie)
    end

    :ets.new(@ets_causal_broadcast, [:named_table, :public, read_concurrency: true])
    :ets.new(@ets_crdt_manager, [:named_table, :public, read_concurrency: true])
    :ets.new(@ets_neighbor_handler, [:named_table, :public, read_concurrency: true])
    :ets.new(@ets_echo_wave, [:named_table, :public, read_concurrency: true])
    :ets.new(@ets_reliable_transport, [:named_table, :public, read_concurrency: true])

    Supervisor.start_link(children(), strategy: :one_for_one, name: P2PDocs.Supervisor)
  end

  @doc """
  This function stops the P2PDocs application.
  It stops all the child processes and cleans up any resources used by the application.
  """
  @impl true
  def stop(_state) do
    Logger.info("Stopping P2PDocs application...")
    # Stop all the children processes
    Supervisor.stop(P2PDocs.Supervisor, :normal, 5000)

    # placeholder for any other cleanup tasks

    # Cleanup of ets tables
    :ets.delete(@ets_causal_broadcast)
    :ets.delete(@ets_crdt_manager)
    :ets.delete(@ets_neighbor_handler)
    :ets.delete(@ets_echo_wave)
    :ets.delete(@ets_reliable_transport)

    :ok
  end

  # @doc """
  # This function defines the child processes that will be supervised by the application.
  # It includes the API server, the neighbor handler, and any other necessary components.
  # Each child process is defined with its module and any necessary arguments.
  # """
  defp children do
    if Mix.env() == :test do
      []
    else
      node_id = node()

      [
        # Registry per websocket
        P2PDocs.PubSub,
        {P2PDocs.API.Server, %{}},
        {P2PDocs.Network.NeighborHandler, node_id},
        {P2PDocs.CRDT.Manager, [peer_id: node_id]},
        {P2PDocs.Network.CausalBroadcast, [my_id: node_id]},
        {P2PDocs.Network.EchoWave, {node_id, []}},
        {P2PDocs.Network.ReliableTransport, [node_id: node_id]}
      ]
    end
  end
end
