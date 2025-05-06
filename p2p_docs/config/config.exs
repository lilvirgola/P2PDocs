import Config

# This is the configuration file for the P2PDocs application.
# It contains settings for the API server, network parameters, and other application-specific configurations.

# NeighborHandler configuration
config(:p2p_docs, P2PDocs.Network.NeighborHandler,
  port: 45892,
  mcast_addr: {224, 1, 1, 1},
  mcast_if: {192, 168, 1, 1},
  iface: {0, 0, 0, 0},
  ttl: 4,
  interval: 5_000,
  secret: "default"
)

# API server configuration
config(:p2p_docs, P2PDocs.API.Server, port: 4000)
