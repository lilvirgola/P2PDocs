# Set a test node name if needed
IO.inspect(Application.get_env(:p2p_docs, :neighbor_handler), label: "NeighborHandler Config")
Application.put_env(:kernel, :node_name, :"testnode@127.0.0.1")
ExUnit.start()
