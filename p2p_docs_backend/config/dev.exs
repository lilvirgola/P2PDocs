import Config
# This is the configuration file for the P2PDocs application.
# It contains settings for the API server, network parameters, and other application-specific configurations.

config :p2p_docs, :vector_clock,
  # The module to use for vector clock implementation
  module: P2PDocs.Network.NaiveVectorClock

# CausalBroadcast configuration (injecting the module to use)
config :p2p_docs, :causal_broadcast,
  module: P2PDocs.Network.CausalBroadcast,
  ets_table: :causal_broadcast_state

# NeighborHandler configuration
config :p2p_docs, :neighbor_handler,
  module: P2PDocs.Network.NeighborHandler,
  ets_table: :neighbor_handler_state,
  cookie: :default

# CRDT Manager configuration
config :p2p_docs, :crdt_manager,
  module: P2PDocs.CRDT.Manager,
  ets_table: :crdt_manager_state

# API server configuration
config :p2p_docs, :api,
  module: P2PDocs.API.Server,
  ets_table: :api_server_state,
  port: 4000

# Echo wave configuration
config :p2p_docs, :echo_wave,
  module: P2PDocs.Network.EchoWave,
  ets_table: :echo_wave_state

# Reliable Transport configuration
config :p2p_docs, :reliable_transport,
  module: P2PDocs.Network.ReliableTransport,
  ets_table: :reliable_transport_state,
  timeout: 5000

# config :logger, :default_handler, false
