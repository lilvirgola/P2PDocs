# P2P_Docs

## Quick Start

### 1. Clone & Setup
```bash
git clone https://github.com/lilvirgola/ProgettoSistemiDistribuiti.git
cd p2p_docs
mix deps.get
```
### 2. Start Nodes
Open separate terminals:
Terminal 1 (Node 1)
```bash
iex --name node1@127.0.0.1 -S mix
```
Terminal 2 (Node 2)
```bash
iex --name node2@127.0.0.1 -S mix
```

The neighbor handler and causalbrodcast modules both start automatically with the supervisor on the P2PDocs.Application module

### 3. Send a broadcast message (for testing)
just write
```elixir
P2PDocs.Network.CausalBroadcast.broadcast("message")
```
message can be any type, r