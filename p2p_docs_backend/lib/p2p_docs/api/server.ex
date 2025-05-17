defmodule P2PDocs.API.Server do
  @moduledoc """
  A simple HTTP server using Plug and Cowboy to serve the API.
  This module is responsible for starting the server and defining its child specification.
  """

  def child_spec(_) do
    Plug.Cowboy.child_spec(
    scheme: :http,
       plug: P2PDocs.API.Router,
       options: [
         port: 4000,
         dispatch: [
           {:_, [
             {"/ws", P2PDocs.API.WebSocket.Handler, []},
             {:_, Plug.Cowboy.Handler, {P2PDocs.API.Router, []}}
           ]}
         ]
       ]
    )
  end
end
