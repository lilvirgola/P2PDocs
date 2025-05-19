# Set a test node name if needed
ExUnit.start()

# Define dynamic mocks
Mox.defmock(P2PDocs.Network.ReliableTransportMock, for: P2PDocs.Network.ReliableTransport)
Mox.defmock(P2PDocs.Network.CausalBroadcastMock, for: P2PDocs.Network.CausalBroadcast)
Mox.defmock(P2PDocs.Network.NeighborHandlerMock, for: P2PDocs.Network.NeighborHandler)

# 2. Override the config settings (similar to adding these to config/test.exs)
Application.put_env(:p2p_docs, :reliable_transport, P2PDocs.Network.ReliableTransportMock)
Application.put_env(:p2p_docs, :causal_broadcast, module: P2PDocs.Network.CausalBroadcastMock)
Application.put_env(:p2p_docs, :neighbor_handler, module: P2PDocs.Network.NeighborHandlerMock)
