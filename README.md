# Distributed Systems Project - P2PDocs

**Academic Year:** [2024/2025]  
**University of Udine: DMIF**\
**Team members:**  
- [Alessandro De Biasi] (@lilvirgola)  
- [Alessandro Minisini] (@alemini18)  
- [Nazareno Piccin] (@Nackha1)

## 📌 Project Description

**P2PDocs** is a decentralized collaborative text editor that implements a serverless architecture, eliminating single points of failure inherent in client-server models. The system enables real-time concurrent editing through direct peer-to-peer communication in a dynamic network topology.

Users should be able to edit the text even while offline, and the system should automatically resolve emerging conflicts once the connection is re-established.

## Quick Start

### 1. Clone & Setup

```bash
git clone https://github.com/lilvirgola/P2PDocs.git
cd P2PDocs
```

### 2. Start a Node
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

## Docs

Compiling and viewing the Elixir documentation of the backend can be done with the following commands:

```bash
cd p2p_docs_backend
mix docs -f html --open
```
