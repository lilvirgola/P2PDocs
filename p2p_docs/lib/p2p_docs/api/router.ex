defmodule P2PDocs.API.Router do
  use Plug.Router

  @moduledoc """
  In this module, we define the API routes for the P2PDocs application.
  The API allows for the retrieval and storage of documents using a simple HTTP interface.
  """

  plug(:match)
  plug(:dispatch)

  # @doc """
  # This route handles GET requests to retrieve a document by its ID.
  # """
  get "/docs/:id" do
    id = conn.params["id"]
    send_resp(conn, 200, Jason.encode!(id || %{}))
  end

  # @doc """
  # This route handles POST requests to store a document.
  # It expects a JSON body containing the document data.
  # """
  post "/docs/:id" do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    {:ok, _data} = Jason.decode(body)
    send_resp(conn, 200, "OK")
  end

  # if nothing matches the above routes, we return a 404 error
  match _ do
    send_resp(conn, 404, "Not found")
  end
end
