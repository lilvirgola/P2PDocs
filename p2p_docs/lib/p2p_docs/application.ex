defmodule P2PDocs.Application do
  @moduledoc """
  The main application module for the P2PDocs application.
  This module is responsible for starting the application and its supervision tree.
  It includes the API server and any other necessary components.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the API server
      {P2PDocs.API.Server, []},
    ]

    opts = [strategy: :one_for_one, name: P2pDocs.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
