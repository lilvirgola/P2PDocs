defmodule P2PDocs.Application do
  @moduledoc """
  The main application module for the P2PDocs application.
  This module is responsible for starting the application and its supervision tree.
  It includes the API server and any other necessary components.
  """

  use Application

  @neighbor_handler Application.compile_env(:p2p_docs, :neighbor_handler)[:module] ||
                      P2PDocs.Network.NeighborHandler
  @causal_broadcast Application.compile_env(:p2p_docs, :causal_broadcast)[:module] ||
                      P2PDocs.Network.CausalBroadcast
  @ets_causal_broadcast Application.compile_env(:p2p_docs, :causal_broadcast)[:ets_table] ||
                          :causal_broadcast_state
  @crdt_manager Application.compile_env(:p2p_docs, :crdt_manager)[:module] ||
                  P2PDocs.CRDT.Manager
  @api_server Application.compile_env(:p2p_docs, :api)[:module] ||
                P2PDocs.API.Server

  @impl true
  def start(_type, _args) do
    # # Only create ETS tables if not in test environment or if needed
    # unless Mix.env() == :test do
    #   :ets.new(@ets_crdt_manager, [:named_table, :public, read_concurrency: true])

    # end
    :ets.new(@ets_causal_broadcast, [:named_table, :public, read_concurrency: true])
    IO.inspect(@neighbor_handler, label: "ACTUAL NEIGHBOR HANDLER MODULE")

    Supervisor.start_link(children(), strategy: :one_for_one, name: P2PDocs.Supervisor)
  end

  defp children do
    node_id = if Mix.env() == :test, do: :test_node, else: node()

    [
      {@api_server, []},
      {@neighbor_handler, []},
      {@causal_broadcast, [my_id: node_id]},
      {@crdt_manager, [peer_id: node_id]},
      {Registry, keys: :unique, name: :echo_registry}
    ]
  end
end
