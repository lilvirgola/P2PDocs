defmodule P2PDocs.Application do
  @moduledoc """
  The main application module for the P2PDocs application.
  This module is responsible for starting the application and its supervision tree.
  It includes the API server and any other necessary components.
  """
  require Logger

  use Application

  @causal_broadcast Application.compile_env(:p2p_docs, :causal_broadcast)[:module] ||
                      P2PDocs.Network.CausalBroadcast
  @ets_causal_broadcast Application.compile_env(:p2p_docs, :causal_broadcast)[:ets_table] ||
                          :causal_broadcast_state
  @crdt_manager Application.compile_env(:p2p_docs, :crdt_manager)[:module] ||
                  P2PDocs.CRDT.Manager
  @ets_crdt_manager Application.compile_env(:p2p_docs, :crdt_manager)[:ets_table] ||
                      :crdt_manager_state
  @api_server Application.compile_env(:p2p_docs, :api)[:module] ||
                P2PDocs.API.Server
  @cookie Application.compile_env(:p2p_docs, :neighbor_handler)[:cookie] ||
            :default
  @ets_neighbor_handler Application.compile_env(:p2p_docs, :neighbor_handler)[:ets_table] ||
                          :neighbor_handler_state

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
    # IO.inspect(@neighbor_handler, label: "ACTUAL NEIGHBOR HANDLER MODULE")

    Supervisor.start_link(children(), strategy: :one_for_one, name: P2PDocs.Supervisor)
  end

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
    # :ets.delete(@ets_api_server)
    :ok
  end

  defp children do
    node_id = if Mix.env() == :test, do: :test_node, else: node()

    [
      #{@api_server, []},
      {P2PDocs.Network.NeighborHandler, []},
      {@crdt_manager, [peer_id: node_id]},
      {@causal_broadcast, [my_id: node_id]},
      {P2PDocs.Network.EchoWave, {node_id, []}},
      {P2PDocs.Network.ReliableTransport, [node_id: node_id]}
    ]
  end
end
