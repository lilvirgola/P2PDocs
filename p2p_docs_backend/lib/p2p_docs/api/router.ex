defmodule P2PDocs.API.Router do
  use Plug.Router
  import Plug.Conn

  @moduledoc """
  This module implements the API router for the P2PDocs application.
  It handles incoming HTTP requests and routes them to the appropriate handlers.
  It also manages WebSocket connections for real-time communication.
  """

  plug(:match)
  plug(:dispatch)

  get "/ws" do
    if get_req_header(conn, "upgrade") == ["websocket"] do
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> upgrade_adapter(:websocket, {P2PDocs.API.WebSocket.Handler, %{}})
    else
      send_resp(conn, 400, "WebSocket connection required")
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
