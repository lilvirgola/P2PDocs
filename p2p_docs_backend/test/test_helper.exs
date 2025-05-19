# Set a test node name if needed
ExUnit.start()

# Define dynamic mocks
Mox.defmock(P2PDocs.Network.ReliableTransportMock, for: P2PDocs.Network.ReliableTransport)
Mox.defmock(P2PDocs.Network.CausalBroadcastMock, for: P2PDocs.Network.CausalBroadcast)

# 2. Override the config settings (similar to adding these to config/test.exs)
Application.put_env(:p2p_docs, :reliable_transport, P2PDocs.Network.ReliableTransportMock)
Application.put_env(:p2p_docs, :causal_broadcast, P2PDocs.Network.CausalBroadcastMock)
