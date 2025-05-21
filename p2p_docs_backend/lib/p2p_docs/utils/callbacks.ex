defmodule P2PDocs.Utils.Callbacks do

def causal_broadcast(), do: Application.get_env(:p2p_docs, :causal_broadcast, P2PDocs.Network.CausalBroadcast)[:module]
def neighbor_handler(), do: Application.get_env(:p2p_docs, :neighbor_handler, P2PDocs.Network.NeighborHandler)[:module]
def echo_wave(), do: Application.get_env(:p2p_docs, :echo_wave, P2PDocs.Network.EchoWave)[:module]
def crdt_text(), do: Application.get_env(:p2p_docs, :crdt_text, P2PDocs.CRDT.CrdtText)
def auto_saver(), do: Application.get_env(:p2p_docs, :auto_saver, P2PDocs.CRDT.AutoSaver)
def handler(), do: Application.get_env(:p2p_docs, :ws_handler, P2PDocs.API.WebSocket.Handler)
def reliable_transport(), do: Application.get_env(:p2p_docs, :reliable_transport, ReliableTransport)[:module]
end