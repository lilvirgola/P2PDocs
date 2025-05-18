defmodule P2PDocs.CRDT.OSTree.Node do
  @moduledoc """
  Internal node struct for the AVL order-statistics tree.
  Fields:
    - 'value': the stored value
    - 'left': left child (another 'OSTree.Node' or 'nil')
    - 'right': right child (another 'OSTree.Node' or 'nil')
    - 'height': height of this subtree
    - 'size': number of nodes in this subtree (including self)
  """
  defstruct value: nil,
            left: nil,
            right: nil,
            height: 1,
            size: 1
end

defmodule P2PDocs.CRDT.OSTree do
  @moduledoc """
  An AVL order-statistics tree with custom comparator, supporting
  insertion, deletion, and k-th smallest element selection in O(log n).
  """
  alias __MODULE__, as: OSTree
  alias OSTree.Node

  @type comparator :: (any(), any() -> integer())
  defstruct comparator: nil, root: nil

  @doc """
  Create a new, empty order-statistics tree with the given comparator.
  """
  @spec new(comparator()) :: %OSTree{}
  def new(comp) when is_function(comp, 2) do
    %OSTree{comparator: comp, root: nil}
  end

  @doc """
  Get size of the tree.
  """
  @spec get_size(%OSTree{}) :: non_neg_integer()
  def get_size(%OSTree{} = state) do
    size(state.root)
  end

  @doc """
  Get height of the tree.
  """
  @spec get_height(%OSTree{}) :: non_neg_integer()
  def get_height(%OSTree{} = state) do
    height(state.root)
  end

  @doc """
  Insert a value into the tree. Duplicates are ignored.
  """
  @spec insert(%OSTree{}, any()) :: %OSTree{}
  def insert(%OSTree{comparator: comp, root: root} = tree, value) do
    %{tree | root: comp_insert(comp, root, value)}
  end

  @doc """
  Delete a value from the tree. If absent, no change.
  """
  @spec delete(%OSTree{}, any()) :: %OSTree{}
  def delete(%OSTree{comparator: comp, root: root} = tree, value) do
    %{tree | root: comp_delete(comp, root, value)}
  end

  @doc """
  Return the k-th smallest element (1-based). Returns 'nil' if out of bounds.
  """
  @spec kth_element(%OSTree{}, integer()) :: any() | nil
  def kth_element(%OSTree{root: root}, k) when is_integer(k) and k > 0 do
    select(root, k)
  end

  def kth_element(_, _) do
    nil
  end

  @doc """
  Return the position of an element (1-based). Returns 'nil' if not found.
  """
  @spec index_by_element(%OSTree{}, any()) :: integer() | nil
  def index_by_element(%OSTree{root: root, comparator: comp}, element) do
    find_by_element(comp, root, element)
  end

  def index_by_element(_, _) do
    nil
  end

  @spec to_list(%OSTree{}) :: [any()]
  def to_list(%OSTree{root: root}) do
    inorder(root)
  end

  def to_graphviz(%OSTree{root: root}) do
    graphify(root)
  end

  # Helpers ---------------------------------------------------------------
  defp height(nil) do
    0
  end

  defp height(%Node{height: h}) do
    h
  end

  defp size(nil) do
    0
  end

  defp size(%Node{size: s}) do
    s
  end

  defp update(node) do
    %Node{
      node
      | height: 1 + max(height(node.left), height(node.right)),
        size: 1 + size(node.left) + size(node.right)
    }
  end

  defp balance_factor(nil) do
    0
  end

  defp balance_factor(%Node{} = node) do
    height(node.left) - height(node.right)
  end

  defp rotate_right(%Node{left: %Node{} = l} = node) do
    new_right = %Node{node | left: l.right} |> update()
    %Node{l | right: new_right} |> update()
  end

  defp rotate_left(%Node{right: %Node{} = r} = node) do
    new_left = %Node{node | right: r.left} |> update()
    %Node{r | left: new_left} |> update()
  end

  defp rebalance(node) do
    node = update(node)
    bf = balance_factor(node)

    cond do
      bf > 1 and balance_factor(node.left) < 0 ->
        # Left-Right case
        %Node{node | left: rotate_left(node.left)} |> rotate_right()

      bf > 1 ->
        # Left-Left
        rotate_right(node)

      bf < -1 and balance_factor(node.right) > 0 ->
        # Right-Left
        %Node{node | right: rotate_right(node.right)} |> rotate_left()

      bf < -1 ->
        # Right-Right
        rotate_left(node)

      true ->
        node
    end
  end

  # Insert with balancing
  defp comp_insert(_comp, nil, value) do
    %Node{value: value}
  end

  defp comp_insert(comp, %Node{value: v, left: l, right: r} = node, value) do
    case comp.(value, v) do
      x when x < 0 ->
        %Node{node | left: comp_insert(comp, l, value)} |> rebalance()

      x when x > 0 ->
        %Node{node | right: comp_insert(comp, r, value)} |> rebalance()

      _ ->
        node
    end
  end

  # Delete with balancing
  defp comp_delete(_comp, nil, _value) do
    nil
  end

  defp comp_delete(comp, %Node{value: v, left: l, right: r} = node, value) do
    node =
      case comp.(value, v) do
        x when x < 0 ->
          %Node{node | left: comp_delete(comp, l, value)}

        x when x > 0 ->
          %Node{node | right: comp_delete(comp, r, value)}

        _ ->
          cond do
            l == nil and r == nil ->
              nil

            l == nil ->
              r

            r == nil ->
              l

            true ->
              succ = min_node(r)
              %Node{node | value: succ.value, right: comp_delete(comp, r, succ.value)}
          end
      end

    if node do
      rebalance(node)
    else
      nil
    end
  end

  defp min_node(%Node{left: nil} = node) do
    node
  end

  defp min_node(%Node{left: l}) do
    min_node(l)
  end

  # k-th smallest selection
  defp select(nil, _) do
    nil
  end

  defp select(%Node{value: v, left: l, right: r}, k) do
    left_size = size(l)

    cond do
      k == left_size + 1 -> v
      k <= left_size -> select(l, k)
      true -> select(r, k - left_size - 1)
    end
  end

  defp find_by_element(_, nil, _) do
    nil
  end

  defp find_by_element(comp, %Node{value: v, left: l, right: r}, element) do
    left_size = size(l)

    case comp.(element, v) do
      x when x < 0 -> find_by_element(comp, l, element)
      x when x > 0 -> safe_add(left_size + 1, find_by_element(comp, r, element))
      0 -> left_size + 1
    end
  end

  defp inorder(nil) do
    []
  end

  defp inorder(%Node{value: v, left: l, right: r}) do
    inorder(l) ++ [v] ++ inorder(r)
  end

  defp graphify(nil) do
    Map.new()
  end

  defp graphify(%Node{value: v, left: l, right: r}) do
    left_graph = graphify(l)
    right_graph = graphify(r)

    Map.merge(left_graph, right_graph)
    |> Map.merge(%{
      v =>
        cond do
          l != nil and r != nil -> [l.value, r.value]
          l -> [l.value]
          r -> [r.value]
          true -> []
        end
    })
  end

  defp safe_add(_, nil) do
    nil
  end

  defp safe_add(a, b) when is_integer(a) and is_integer(b) do
    a + b
  end
end
