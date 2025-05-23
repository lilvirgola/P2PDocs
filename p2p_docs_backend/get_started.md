# Getting Started

## Quick Start

### 1. Clone & Setup

```bash
git clone https://github.com/lilvirgola/P2PDocs.git
cd P2PDocs
```

### 2. Start Node
Ensure that Docker is correctly installed.

Inside `docker-compose.yml` override the environment variable `ERL_NODE_NAME` with your current IP, then run on terminal:

```bash
sudo docker compose up --build
```

Al the modules start automatically with the supervisor on the P2PDocs.Application module. The front-end can be found on

```bash
localhost:3000
```

Follow the instructions on the browser and use it!

## Testing

Unit tests for each module are implemented with Elixir’s built-in ExUnit framework and, where needed, the Mox library for mocking inter-module calls. To run them, execute:

```bash
cd p2p_docs_backend/
mix deps.get
mix test
```

The output will indicate which tests passed and highlight any failures.

### View Generated Topology in EchoWave tests

The EchoWave unit test automatically generates a dot file that contains the representation of the random connected graph used to test the module. If you want to visualize it, run the following command:

```bash
dot -Tsvg -O random_topology.dot

```

### Multi-Node (System-Wide) Tests

End-to-end testing across multiple instances is performed via custom scripts rather than a built-in framework.

`tests/start_n_instances_for_tests.sh <n>` 
Launches `n` containers of **P2PDocs**, all attached to the dedicated Docker network `172.16.1.0/24`.  
Each node’s frontend is exposed at `localhost:<3000+idx>`, where `idx` is the peer number.

In the `tests/` directory:

- `disconnect.sh <idx>` Disconnects peer `idx` from the network.
- `connect.sh <idx>` Reconnects peer `idx` to the network.


To inspect logs for a single peer numbered as `idx`:

```bash
sudo docker logs test<idx>
```

## Docs

Compiling and viewing the Elixir documentation of the backend can be done with the following commands:

```bash
cd p2p_docs_backend
mix docs -f html --open
```