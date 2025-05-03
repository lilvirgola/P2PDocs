defmodule CrdtText do
  @moduledoc """
  Operation-based CRDT for collaborative text editing using an LSEQ-inspired allocation.
  Supports local and remote insertions and deletions.
  """

  alias __MODULE__, as: CRDT
  alias CustomBroadcast, as: Broadcast
  alias OSTree

  @initial_base 32
  @boundary 15

  defstruct [
    # Ordered list of characters in the document
    chars: %OSTree{},
    # Map of id => position of each character
    pos_by_id: %{},
    # Map of depth => :plus | :minus allocation strategies
    strategies: %{},
    # Unique identifier for this replica
    peer_id: nil,
    # Counter for generating unique character IDs
    counter: 1
  ]

  @type char_id :: {String.t(), non_neg_integer()}
  @type pos_digit :: {non_neg_integer(), String.t()}
  @type position :: [pos_digit()]
  @type crdt_char :: %{id: char_id(), pos: position(), value: binary()}
  @type t :: %CRDT{
          chars: %OSTree{},
          pos_by_id: Map.t(),
          strategies: %{optional(non_neg_integer()) => :plus | :minus},
          peer_id: String.t(),
          counter: non_neg_integer()
        }

  @doc """
  Initialize a new CRDT state for the given peer, including sentinel boundaries.
  """
  @spec new(String.t()) :: t()
  def new(peer_id) do
    begin_marker = %{id: {:__begin__, 0}, pos: [{0, "$"}], value: nil}
    end_marker = %{id: {:__end__, 0}, pos: [{@initial_base, "$"}], value: nil}

    ostree =
      OSTree.new(fn %{pos: a}, %{pos: b} ->
        cond do
          a == b -> 0
          a < b -> -1
          true -> 1
        end
      end)

    %CRDT{
      chars: OSTree.insert(OSTree.insert(ostree, begin_marker), end_marker),
      pos_by_id: %{{:__begin__, 0} => [{0, "$"}], {:__end__, 0} => [{@initial_base, "$"}]},
      strategies: %{},
      peer_id: peer_id
    }
  end

  @doc """
  Perform a local insertion of `value` at index `index`, broadcast the operation.
  Returns the updated state.
  """
  @spec insert_local(t(), non_neg_integer(), binary()) :: t()
  def insert_local(%CRDT{chars: chars} = state, index, value) do
    left_char =
      case OSTree.kth_element(chars, index) do
        nil -> raise ArgumentError, "Index #{index} out of bounds"
        val -> val
      end

    right_char =
      case OSTree.kth_element(chars, index + 1) do
        nil -> raise ArgumentError, "Index #{index + 1} out of bounds"
        val -> val
      end

    allocate_and_insert(state, left_char, right_char, value)
  end

  # Allocates a new position between left_id and right_id, inserts the char, broadcasts it
  defp allocate_and_insert(
         %CRDT{} = state,
         left,
         right,
         value
       ) do
    left_pos = left.pos
    right_pos = right.pos

    {new_pos, updated_strategies} =
      allocate_position(left_pos, right_pos, [], 1, state.strategies, state.peer_id)

    new_id = {state.peer_id, state.counter}
    new_char = %{id: new_id, pos: new_pos, value: value}

    new_chars = OSTree.insert(state.chars, new_char)
    new_pos_by_id = Map.put(state.pos_by_id, new_id, new_pos)

    unless left_pos < new_pos and new_pos < right_pos do
      raise "Allocation error: new position does not satisfy intention preservation"
    end

    Broadcast.sendMessage(:insert, new_char)

    %CRDT{state | chars: new_chars, counter: state.counter + 1, strategies: updated_strategies, pos_by_id: new_pos_by_id}
  end

  @doc """
  Perform a local deletion at index `index`, broadcast the operation.
  Returns the updated state.
  """
  @spec delete_local(t(), non_neg_integer()) :: t()
  def delete_local(%CRDT{chars: chars} = state, index) do
    # Inline get_char_at!
    target_id =
      case OSTree.kth_element(chars, index) do
        nil -> raise ArgumentError, "Index #{index} out of bounds"
        %{id: id} -> id
      end

    delete_by_id(state, target_id)
  end

  # Deletes a character by its ID and broadcasts the operation
  defp delete_by_id(%CRDT{chars: chars, pos_by_id: pos_by_id} = state, target_id) do
    Broadcast.sendMessage(:delete, target_id)
    filtered = OSTree.delete(chars, %{id: target_id, pos: Map.fetch(pos_by_id, target_id), value: nil})
    %CRDT{state | chars: filtered}
  end

  @doc """
  Apply a remote insert operation, merging the new char and sorting by position.
  """
  @spec apply_remote_insert(t(), crdt_char()) :: t()
  def apply_remote_insert(%CRDT{chars: chars} = state, char) do
    new_chars = OSTree.insert(chars, char)
    %CRDT{state | chars: new_chars}
  end

  @doc """
  Apply a remote delete operation by removing the char with `target_id`.
  """
  @spec apply_remote_delete(t(), char_id()) :: t()
  def apply_remote_delete(%CRDT{chars: chars, pos_by_id: pos_by_id} = state, target_id) do
    filtered = OSTree.delete(chars, %{id: target_id, pos: Map.fetch(pos_by_id, target_id), value: nil})
    %CRDT{state | chars: filtered}
  end

  # -----------------------------------------------------------------------
  # Internal LSEQ allocation helpers retained for core logic
  # -----------------------------------------------------------------------

  defp allocate_position(p, q, acc, depth, strategies, peer_id) do
    {updated_strategies, s} =
      case Map.fetch(strategies, depth) do
        {:ok, val} ->
          {strategies, val}

        :error ->
          val =
            if :rand.uniform(2) do
              :plus
            else
              :minus
            end

          {Map.put(strategies, depth, val), val}
      end

    {p_head, q_head} = {hd(p), hd(q)}
    interval = elem(q_head, 0) - elem(p_head, 0)

    cond do
      interval > 1 ->
        digit =
          compute_position_digit(
            elem(p_head, 0),
            elem(q_head, 0),
            min(interval - 1, @boundary),
            s,
            peer_id
          )

        {acc ++ [digit], strategies}

      interval in [0, 1] ->
        next_p = tl(p) ++ [{0, peer_id}]

        next_q =
          if interval == 0 do
            tl(q) ++ [{base_for(depth + 1), peer_id}]
          else
            [{base_for(depth + 1), peer_id}]
          end

        allocate_position(next_p, next_q, acc ++ [p_head], depth + 1, updated_strategies, peer_id)

      true ->
        raise "Illegal boundaries between positions #{inspect(p)} and #{inspect(q)}"
    end
  end

  defp base_for(1), do: @initial_base
  defp base_for(depth) when depth > 1, do: base_for(depth - 1) * 2

  defp compute_position_digit(left, _right, step, :plus, peer_id) do
    {left + :rand.uniform(step), peer_id}
  end

  defp compute_position_digit(_left, right, step, :minus, peer_id) do
    {right - :rand.uniform(step), peer_id}
  end
end
