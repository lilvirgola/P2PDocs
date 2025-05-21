defmodule P2PDocs.CRDT.CrdtText do
  @moduledoc """
  Operation-based CRDT for collaborative text editing using an adaptive LSEQ-inspired allocation.
  Supports local and remote insertions and deletions.
  """

  import Bitwise
  require Logger

  alias P2PDocs.CRDT.OSTree
  alias __MODULE__, as: CRDT

  @initial_base 32
  @boundary 15

  @type char_id :: {String.t(), non_neg_integer()}
  @type pos_digit :: {non_neg_integer(), String.t()}
  @type position :: [pos_digit()]
  @type crdt_char :: %{id: char_id(), pos: position(), value: binary()}
  @type t :: %CRDT{
          chars: OSTree.t(),
          pos_by_id: %{optional(char_id()) => position()},
          strategies: %{optional(non_neg_integer()) => :plus | :minus},
          peer_id: String.t(),
          counter: non_neg_integer()
        }

  defstruct chars: nil,
            pos_by_id: %{},
            strategies: %{},
            peer_id: nil,
            counter: 1

  # Public API

  @doc """
  Initializes a new CRDT state for `peer_id`.
  """
  @callback new(peer_id :: binary) :: t
  @spec new(String.t()) :: t()
  def new(peer_id) do
    tree = OSTree.new(fn a, b -> compare_pos(a.pos, b.pos) end)
    %CRDT{chars: tree, peer_id: peer_id}
  end

  @doc """
  Inserts `value` at local `index`, returning the char and updated state.
  """
  @callback insert_local(state :: t, index :: non_neg_integer, value :: binary) ::
              {crdt_char, any}
  @spec insert_local(t(), non_neg_integer(), binary()) :: {crdt_char(), t()}
  def insert_local(state, index, value) do
    left = get_at(state, index - 1)
    right = get_at(state, index)
    do_insert(state, left, right, value)
  end

  @doc """
  Deletes local char at `index`, returning its id and updated state.
  """
  @callback delete_local(state :: t, index :: non_neg_integer) :: {char_id, t}
  @spec delete_local(t(), non_neg_integer()) :: {char_id(), t()}
  def delete_local(%CRDT{} = state, index) do
    char = get_at(state, index)
    new_tree = OSTree.delete(state.chars, char)

    {char.id,
     %CRDT{
       state
       | chars: new_tree,
         pos_by_id: Map.delete(state.pos_by_id, char.id)
     }}
  end

  @doc """
  Applies a remote insert operation if not already present.
  Returns the insertion index (or nil) and updated state.
  """
  @callback apply_remote_insert(state :: t, char :: crdt_char) :: {integer | nil, t}
  @spec apply_remote_insert(t(), crdt_char()) :: {integer() | nil, t()}
  def apply_remote_insert(%CRDT{} = state, %{id: id, pos: pos} = char) do
    if Map.has_key?(state.pos_by_id, id) do
      {nil, state}
    else
      new_tree = OSTree.insert(state.chars, char)
      index = OSTree.index_by_element(new_tree, char)

      {index,
       %CRDT{
         state
         | chars: new_tree,
           pos_by_id: Map.put(state.pos_by_id, id, pos)
       }}
    end
  end

  @doc """
  Applies a remote delete operation if the id exists.
  Returns the removed index (or nil) and updated state.
  """
  @callback apply_remote_delete(state :: t, target_id :: char_id) :: {integer | nil, t}
  @spec apply_remote_delete(t(), char_id()) :: {integer() | nil, t()}
  def apply_remote_delete(%CRDT{} = state, target_id) do
    case Map.pop(state.pos_by_id, target_id) do
      {nil, _} ->
        {nil, state}

      {pos, new_map} ->
        # Comparator function uses only the pos parameter, so the others do not matter
        index = OSTree.index_by_element(state.chars, %{id: nil, pos: pos, value: nil})
        new_tree = OSTree.delete(state.chars, %{id: nil, pos: pos, value: nil})

        {index, %CRDT{state | chars: new_tree, pos_by_id: new_map}}
    end
  end

  @doc """
  Converts the CRDT to a list of characters (plain text).
  """
  @spec to_plain_text(t()) :: [binary()]
  def to_plain_text(%CRDT{chars: chars}) do
    OSTree.to_list(chars) |> Enum.map(& &1.value)
  end

  # Private Helpers

  # Compare two positions lexicographically
  defp compare_pos(a, b) do
    cond do
      a > b -> 1
      a < b -> -1
      true -> 0
    end
  end

  # Safe element retrieval: returns a boundary marker for out-of-bounds
  defp get_at(%CRDT{chars: chars}, idx) do
    case OSTree.kth_element(chars, idx) do
      nil -> %{id: "marker", pos: [], value: nil}
      char -> char
    end
  end

  # Performs insertion logic, allocating a new position
  defp do_insert(state, left, right, value) do
    {new_pos, strategies} =
      allocate_position(left.pos, right.pos, state.strategies, state.peer_id)

    new_id = {state.peer_id, state.counter}
    char = %{id: new_id, pos: new_pos, value: value}

    # Ensure the new position lies between left and right
    unless (left.pos < new_pos or left.pos == []) and
             (new_pos < right.pos or right.pos == []) do
      Logger.error(
        "Allocation error: position #{inspect(new_pos)} between #{inspect(left.pos)}" <>
          " and #{inspect(right.pos)} does not satisfy intention preservation"
      )
    end

    tree = OSTree.insert(state.chars, char)

    {char,
     %CRDT{
       state
       | chars: tree,
         pos_by_id: Map.put(state.pos_by_id, new_id, new_pos),
         strategies: strategies,
         counter: state.counter + 1
     }}
  end

  # LSEQ-inspired allocation dispatcher
  defp allocate_position(p, q, strategies, peer_id) do
    do_allocate(p, q, [], 1, strategies, peer_id)
  end

  # Recursively allocate position digits
  defp do_allocate(p, q, acc, depth, strategies, peer_id) do
    {strategies, strat} = get_and_update_strategy(strategies, depth)
    {ph, pid} = head(p, 0, peer_id)
    {qh, qid} = head(q, depth, peer_id)
    interval = qh - ph

    cond do
      interval > 1 ->
        step = min(interval - 1, @boundary)
        digit = compute_digit(ph, qh, step, strat, peer_id)
        {acc ++ [digit], strategies}

      interval in [0, 1] ->
        # Handle edge cases and continue to next depth
        p_tail = tail(p)
        q_tail = if interval == 0 and pid >= qid, do: tail(q), else: []

        p_hd =
          if interval == 0 and pid > qid do
            _ =
              Logger.warning(
                "Using wildcard rule between positions #{inspect(p)} and #{inspect(q)}"
              )

            {ph, qid}
          else
            {ph, pid}
          end

        do_allocate(p_tail, q_tail, acc ++ [p_hd], depth + 1, strategies, peer_id)

      true ->
        raise "Illegal boundaries between #{inspect(p)} and #{inspect(q)}"
    end
  end

  # Retrieve or initialize strategy for depth
  defp get_and_update_strategy(strategies, depth) do
    case Map.fetch(strategies, depth) do
      {:ok, strat} ->
        {strategies, strat}

      :error ->
        strat = if :rand.uniform(2) == 1, do: :plus, else: :minus
        {Map.put(strategies, depth, strat), strat}
    end
  end

  defp compute_digit(left, _, step, :plus, peer_id), do: {left + :rand.uniform(step), peer_id}
  defp compute_digit(_, right, step, :minus, peer_id), do: {right - :rand.uniform(step), peer_id}

  defp head([], depth, peer_id), do: {base(depth), peer_id}
  defp head([h | _], _, _), do: h

  defp tail([]), do: []
  defp tail([_ | t]), do: t

  # Calculate base for a given depth
  defp base(0), do: 0
  defp base(depth), do: @initial_base <<< (depth - 1)
end
