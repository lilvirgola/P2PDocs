defmodule P2PDocs.API.Router do
  use Plug.Router
  import Plug.Conn

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
