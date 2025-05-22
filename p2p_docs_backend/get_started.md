# Getting Started

## Quick Start

### 1. Clone & Setup

```bash
git clone https://github.com/lilvirgola/ProgettoSistemiDistribuiti.git
cd ProgettoSistemiDistribuiti
```

### 2. Start Node
Ensure that Docker is correctly installed. Then run on terminal:

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
mix test
```

The output will indicate which tests passed and highlight any failures.

### Multi-Node (System-Wide) Tests

End-to-end testing across multiple instances is performed via custom scripts rather than a built-in framework.

`start_n_instances_for_tests.sh <n>` 
Launches `n` containers of **P2PDocs**, all attached to the dedicated Docker network `172.16.1.0/24`.  
Each node’s frontend is exposed at `localhost:<3000+n>`.

In the `tests/` directory:

- `disconnect.sh <idx>` Disconnects peer `idx` from the network.
- `connect.sh <idx>` Reconnects peer `idx` to the network.


To inspect logs for a single peer numbered as `idx`:

```bash
sudo docker logs test<idx>
```
