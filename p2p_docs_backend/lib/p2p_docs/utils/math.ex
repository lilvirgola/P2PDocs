defmodule P2PDocs.Utils.Math do
  def ilog(n) when n < 2 do
    0
  end

  def ilog(n) do
    1 + ilog(div(n, 2))
  end
end
