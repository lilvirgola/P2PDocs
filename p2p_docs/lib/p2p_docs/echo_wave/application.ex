# defmodule EchoWave.Application do
#   use Application

#   def start(_type, _args) do
#     children = [
#       {Registry, keys: :unique, name: :echo_registry}
#     ]

#     opts = [strategy: :one_for_one, name: EchoWave.Supervisor]
#     Supervisor.start_link(children, opts)
#   end
# end
