# Set a test node name if needed
ExUnit.start()

# Define dynamic mocks
Mox.defmock(P2PDocs.Network.ReliableTransportMock, for: P2PDocs.Network.ReliableTransport)
Mox.defmock(P2PDocs.Network.CausalBroadcastMock, for: P2PDocs.Network.CausalBroadcast)
Mox.defmock(P2PDocs.Network.NeighborHandlerMock, for: P2PDocs.Network.NeighborHandler)
Mox.defmock(P2PDocs.CRDT.CrdtTextMock, for: P2PDocs.CRDT.CrdtText)
Mox.defmock(P2PDocs.CRDT.AutoSaverMock, for: P2PDocs.CRDT.AutoSaver)
Mox.defmock(P2PDocs.API.WebSocket.HandlerMock, for: P2PDocs.API.WebSocket.Handler)

# 2. Override the config settings (similar to adding these to config/test.exs)
Application.put_env(:p2p_docs, :reliable_transport, P2PDocs.Network.ReliableTransportMock)
Application.put_env(:p2p_docs, :causal_broadcast, module: P2PDocs.Network.CausalBroadcastMock)
Application.put_env(:p2p_docs, :neighbor_handler, module: P2PDocs.Network.NeighborHandlerMock)
Application.put_env(:p2p_docs, :crdt_text, P2PDocs.CRDT.CrdtTextMock)
Application.put_env(:p2p_docs, :auto_saver, P2PDocs.CRDT.AutoSaverMock)
Application.put_env(:p2p_docs, :ws_handler, P2PDocs.API.WebSocket.HandlerMock)
