defmodule P2PDocs.CRDT.CrdtText do
  @moduledoc """
  Operation-based CRDT for collaborative text editing using an adaptive LSEQ-inspired allocation.
  Supports local and remote insertions and deletions.
  """

  import Bitwise

  alias P2PDocs.CRDT.OSTree, as: OSTree

  alias __MODULE__, as: CRDT

  @initial_base 32
  @boundary 15

  defstruct chars: nil,
            pos_by_id: %{},
            strategies: %{},
            peer_id: nil,
            counter: 1

  @type char_id :: {String.t(), non_neg_integer()}
  @type pos_digit :: non_neg_integer()
  @type position :: {[pos_digit()], String.t()}
  @type crdt_char :: %{id: char_id(), pos: position(), value: binary()}
  @type t :: %CRDT{
          chars: OSTree.t(),
          pos_by_id: %{optional(char_id()) => position()},
          strategies: %{optional(non_neg_integer()) => :plus | :minus},
          peer_id: String.t(),
          counter: non_neg_integer()
        }

  @doc """
  Create a new CRDT state for 'peer_id', inserting sentinel bounds.
  """
  @spec new(String.t()) :: t()
  def new(peer_id) do
    [begin_marker, end_marker] = sentinel_markers()

    tree =
      OSTree.new(fn a, b -> compare_pos(a.pos, b.pos) end)
      |> OSTree.insert(begin_marker)
      |> OSTree.insert(end_marker)

    pos_map = %{
      begin_marker.id => begin_marker.pos,
      end_marker.id => end_marker.pos
    }

    %CRDT{
      chars: tree,
      pos_by_id: pos_map,
      strategies: %{},
      peer_id: peer_id
    }
  end

  defp sentinel_markers() do
    [
      %{id: {:begin, 0}, pos: [{0, "$"}], value: nil},
      %{id: {:end, 0}, pos: [{@initial_base, "$"}], value: nil}
    ]
  end

  defp compare_pos(a, b) do
    cond do
      a > b -> 1
      a < b -> -1
      true -> 0
    end
  end

  @doc """
  Locally insert 'value' at index, broadcasting to peers.
  """
  @spec insert_local(t(), non_neg_integer(), binary()) :: {crdt_char(), t()}
  def insert_local(state, index, value) do
    left = get_at!(state, index)
    right = get_at!(state, index + 1)
    do_insert(state, left, right, value)
  end

  defp get_at!(%CRDT{chars: chars}, idx) do
    case OSTree.kth_element(chars, idx) do
      nil -> raise ArgumentError, "Index #{idx} out of bounds"
      val -> val
    end
  end

  defp do_insert(%CRDT{} = state, left, right, value) do
    {new_pos, strategies} =
      allocate_position(
        left.pos,
        right.pos,
        state.strategies,
        state.peer_id
      )

    new_id = {state.peer_id, state.counter}
    char = %{id: new_id, pos: new_pos, value: value}

    # Invariant check
    unless left.pos < new_pos and new_pos < right.pos do
      raise "Allocation error: position #{inspect(new_pos)} between #{inspect(left.pos)}" <>
              " and #{inspect(right.pos)} does not satisfy intention preservation"
    end

    {char,
     %CRDT{
       chars: OSTree.insert(state.chars, char),
       pos_by_id: Map.put(state.pos_by_id, new_id, new_pos),
       strategies: strategies,
       counter: state.counter + 1,
       peer_id: state.peer_id
     }}
  end

  @doc """
  Locally delete element at 'index', broadcasting to peers.
  """
  @spec delete_local(t(), non_neg_integer()) :: {char_id(), t()}
  def delete_local(%CRDT{} = state, index) do
    char = get_at!(state, index + 1)

    new_chars = OSTree.delete(state.chars, char)

    {
      char.id,
      %CRDT{state | chars: new_chars, pos_by_id: Map.delete(state.pos_by_id, char.id)}
    }
  end

  @doc """
  Merge a remote insert operation.
  """
  @spec apply_remote_insert(t(), crdt_char()) :: t()
  def apply_remote_insert(%CRDT{} = state, %{id: id, pos: pos} = char) do
    unless Map.has_key?(state.pos_by_id, id) do
      {:ok,
       %CRDT{
         state
         | chars: OSTree.insert(state.chars, char),
           pos_by_id: Map.put(state.pos_by_id, id, pos)
       }}
    else
      {:ok, state}
    end
  end

  @doc """
  Merge a remote delete operation.
  """
  @spec apply_remote_delete(t(), char_id()) :: t()
  def apply_remote_delete(%CRDT{} = state, target_id) do
    case Map.fetch(state.pos_by_id, target_id) do
      {:ok, val} ->
        pos = val
        # id and value are not used by comparator, so they are not needed for delete
        new_chars = OSTree.delete(state.chars, %{id: nil, pos: pos, value: nil})

        {:ok,
         %CRDT{
           state
           | chars: new_chars,
             pos_by_id: Map.delete(state.pos_by_id, target_id)
         }}

      :error ->
        {:ok, state}
    end
  end

  @spec to_plain_text(t()) :: [binary()]
  def to_plain_text(%CRDT{chars: chars}) do
    Enum.map(OSTree.to_list(chars), fn x -> x.value end)
  end

  # -----------------------------------------------------------------------
  # LSEQ-inspired allocation
  # -----------------------------------------------------------------------

  @spec allocate_position(position(), position(), map(), String.t()) :: {position(), map()}
  defp allocate_position({p, _}, {q, _}, strategies, peer_id) do
    {pos, upd_strategies} = do_allocate(p, q, [], 1, strategies)
    {{pos, peer_id}, upd_strategies}
  end

  defp do_allocate(p, q, acc, depth, strategies) do
    {upd_strategies, strat} = get_and_update_strategy(strategies, depth)

    ph = hd(p)
    qh = hd(q)
    interval = qh - ph

    cond do
      interval > 1 ->
        step = min(interval - 1, @boundary)
        digit = compute_digit(ph, qh, step, strat)
        {acc ++ [digit], upd_strategies}

      interval in [0, 1] ->
        next_p = tl(p) ++ [0]

        next_q =
          if interval == 0 do
            tl(q) ++ [base(depth + 1)]
          else
            [base(depth + 1)]
          end

        do_allocate(next_p, next_q, acc ++ [ph], depth + 1, upd_strategies)

      true ->
        raise "Illegal boundaries between positions #{inspect(p)} and #{inspect(q)}"
    end
  end

  defp get_and_update_strategy(strategies, depth) do
    case Map.fetch(strategies, depth) do
      {:ok, val} ->
        {strategies, val}

      :error ->
        new_strat =
          if :rand.uniform(2) == 1 do
            :plus
          else
            :minus
          end

        {Map.put(strategies, depth, new_strat), new_strat}
    end
  end

  defp base(depth) do
    @initial_base <<< (depth - 1)
  end

  defp compute_digit(left, _, step, :plus) do
    left + :rand.uniform(step)
  end

  defp compute_digit(_, right, step, :minus) do
    right - :rand.uniform(step)
  end
end
