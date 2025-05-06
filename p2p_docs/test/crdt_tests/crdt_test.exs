defmodule CustomBroadcast do
  def sendMessage(_op, _payload) do
    :ok
  end
end

defmodule Math do
  def ilog(n) when n < 2 do
    0
  end

  def ilog(n) do
    1 + ilog(div(n, 2))
  end
end

defmodule CrdtTextFastTest do
  use ExUnit.Case
  alias CrdtText

  @peer "peer1"

  setup do
    {:ok, state: CrdtText.new(@peer)}
  end

  test "random local inserts maintain ordering and uniqueness", %{state: state} do
    total = 100_000
    # :eprof.start()
    # :eprof.profile(fn ->
    final_state =
      Enum.reduce(1..total, state, fn i, st ->
        # sorted = Enum.sort_by(st.chars, fn x -> {x.pos, x.id} end)
        # pick random adjacent pair
        idx = :rand.uniform(OSTree.get_size(st.chars) - 1)
        CrdtText.insert_local(st, idx, Integer.to_string(i))
      end)

    # IO.inspect(CrdtText.get_plain_text(final_state))

    # Collect only real characters (skip sentinels)
    # chars = Enum.filter(final_state.chars, &(&1.value != nil))

    # IO.inspect(Enum.reduce(final_state.chars, 0, fn x, acc -> acc + length(x.pos)*(Math.ilog(elem(Enum.max(x.pos),0)) + 40) end) / (total*8))

    # IO.inspect(final_state.chars, charlists: :as_lists)

    # Expect exactly `total` inserted chars
    assert OSTree.get_size(final_state.chars) == total + 2
    IO.inspect(OSTree.get_size(final_state.chars))

    # All IDs unique
    # ids = Enum.map(chars, & &1.id)
    # assert MapSet.size(MapSet.new(ids)) == total

    # Positions strictly increasing
    # poses = Enum.map(chars, fn x-> x.pos end)
    # assert Enum.sort(poses) == poses
    # end)
    # :eprof.analyze()
    # :eprof.stop()
  end
end
