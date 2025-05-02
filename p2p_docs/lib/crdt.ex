defmodule CrdtText do
  @moduledoc """
  An operation-based CRDT for collaborative text editing using an LSEQ-inspired allocation.

  Supports:
    - local_insert/4
    - local_delete/2
    - remote_insert/2
    - remote_delete/2

  Relies on a Broadcast.sendMessage/2 for propagation.
  """

  alias __MODULE__, as: State
  alias CustomBroadcast, as: Broadcast

  @initial_base 32
  @boundary 15

  defstruct chars: [],
            # depth => :plus | :minus
            strategy_map: %{},
            peer_id: nil,
            counter: 1

  @type char_id :: {String.t(), non_neg_integer()}
  @type pos_digit :: {non_neg_integer(), String.t()}
  @type position :: [pos_digit()]
  @type crdt_char :: %{id: char_id, pos: position, value: binary()}
  @type t :: %State{
          chars: [crdt_char],
          strategy_map: %{optional(non_neg_integer()) => atom()},
          peer_id: String.t(),
          counter: non_neg_integer()
        }

  @doc """
  Create a new CRDT state, initializing sentinel boundaries.
  """
  @spec new(String.t()) :: t()
  def new(peer_id) do
    # Sentinel begin and end
    begin = %{id: {:__begin__, 0}, pos: [{0, "$"}], value: nil}
    end_ = %{id: {:__end__, 0}, pos: [{@initial_base, "$"}], value: nil}
    %State{chars: [begin, end_], strategy_map: %{}, peer_id: peer_id}
  end

  @doc """
  Local insert: compute position via LSEQ, add char, broadcast.
  """
  @spec local_insert(t(), non_neg_integer(), binary()) :: t()
  def local_insert(%State{} = state, pos, value) do
    prev =
      case Enum.fetch(state.chars, pos) do
        {:ok, val} -> val
        :error -> raise ArgumentError, "index #{pos} out of bounds"
      end

    succ =
      case Enum.fetch(state.chars, pos + 1) do
        {:ok, val} -> val
        :error -> raise ArgumentError, "index #{pos + 1} out of bounds"
      end

    # IO.inspect(prev,charlists: :as_lists)
    # IO.inspect(succ,charlists: :as_lists)
    local_insert_via_id(state, prev.id, succ.id, value)
  end

  # @spec local_insert_via_id(t(), char_id(), char_id(), binary()) :: t()
  # Perform local insert given the ids of the boundary characters 
  defp local_insert_via_id(%State{} = state, left_id, right_id, value) do
    p = pos_for(state.chars, left_id)
    q = pos_for(state.chars, right_id)
    #IO.inspect(p)
    #IO.inspect(q)
    {new_pos, strat_map2} = alloc(p, q, [], 1, state.strategy_map, state.peer_id)

    id = {state.peer_id, state.counter}
    new_char = %{id: id, pos: new_pos, value: value}
    new_chars = (state.chars ++ [new_char]) |> Enum.sort_by(fn x -> {x.pos, x.id} end)
    #IO.inspect(new_pos)
    if not (p < new_pos and new_pos < q) do
      raise "ERROR: generated position do not repsect intention preservation!"
    end

    # IO.inspect(new_char, charlists: :as_lists)
    # IO.inspect(" ")

    # -------------------------------------------------------------------------
    Broadcast.sendMessage(:insert, new_char)
    # -------------------------------------------------------------------------

    %State{state | chars: new_chars, counter: state.counter + 1, strategy_map: strat_map2}
  end

  @doc """
  Local delete: remove char locally and broadcast deletion.
  """
  @spec local_delete(t(), non_neg_integer()) :: t()
  def local_delete(%State{} = state, pos) do
    char_to_erase =
      case Enum.fetch(state.chars, pos) do
        {:ok, val} -> val
        :error -> raise ArgumentError, "index #{pos} out of bounds"
      end

    local_delete_via_id(state, char_to_erase.id)
  end

  # Perform the delete given the id of the targeted char
  defp local_delete_via_id(%State{} = state, target_id) do
    # ----------------------------------------------------------------
    Broadcast.sendMessage(:delete, target_id)
    # ----------------------------------------------------------------
    new_chars = Enum.reject(state.chars, &(&1.id == target_id))
    %State{state | chars: new_chars}
  end

  @doc """
  Handle a remote insert operation.
  """
  @spec remote_insert(t(), crdt_char()) :: t()
  def remote_insert(%State{} = state, %{id: _id, pos: _pos, value: _value} = insert_op) do
    new_chars = (state.chars ++ [insert_op]) |> Enum.sort_by(& &1.pos)
    %State{state | chars: new_chars}
  end

  @doc """
  Handle a remote delete operation.
  """
  @spec remote_delete(t(), char_id()) :: t()
  def remote_delete(%State{} = state, target_id) do
    new_chars = Enum.reject(state.chars, &(&1.id == target_id))
    %State{state | chars: new_chars}
  end

  # ------------------------
  # Internal Helpers
  # ------------------------

  # Find position vector for a given char_id
  defp pos_for(chars, id) do
    case Enum.find(chars, &(&1.id == id)) do
      %{pos: pos} -> pos
      nil -> raise "Unknown character id: #{inspect(id)}"
    end
  end

  # LSEQ allocation: returns {new_position, updated_strategy_map}
  defp alloc(p, q, new_pos, depth, strategies, peer_id) do
    # 1) find depth where we have room
    # IO.inspect("p")
    # IO.inspect(p,charlists: :as_lists)
    # IO.inspect("q")
    # IO.inspect(q,charlists: :as_lists)
    {strategies2, s} =
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

    head_p =hd(p)

    head_q =hd(q)

    case elem(head_q, 0) - elem(head_p, 0) do
      x when x > 1 ->
        {new_pos ++ [compute_digit(elem(head_p, 0), elem(head_q, 0), s, peer_id)], strategies2}

      x when x == 1 ->
        updated_pos = new_pos ++ [head_p]
        alloc(tl(p ++ [{0,peer_id}]), [{base_at_depth(depth+1), peer_id}], updated_pos, depth + 1, strategies2, peer_id)

      x when x == 0 ->
        updated_pos = new_pos ++ [head_p]
        alloc(tl(p ++ [{0,peer_id}]), tl(q ++ [{base_at_depth(depth+1),peer_id}]), updated_pos, depth + 1, strategies2, peer_id)

      _x ->
        raise "ERROR: illegal boundaries!"
    end
  end

  # Base size at a given depth: initial_base * 2^(depth-1)
  defp base_at_depth(1) do
    @initial_base
  end

  defp base_at_depth(depth) when depth > 1 do
    base_at_depth(depth - 1) * 2
  end

  defp compute_digit(left_digit, right_digit, strategy, peer_id) do
    step = min((right_digit - left_digit - 1), @boundary)
    case strategy do
      :plus -> {:rand.uniform(step) + left_digit, peer_id}
      :minus -> {right_digit - :rand.uniform(step), peer_id}
    end
  end
end
