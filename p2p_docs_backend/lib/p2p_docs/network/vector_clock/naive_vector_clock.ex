defmodule P2PDocs.Network.NaiveVectorClock do
  @moduledoc """
  This module contains the implementation of a naive vector clock for
  distributed systems. It provides functions to create, update, and compare
  vector clocks, as well as to merge them
  """

  @typedoc """
  A vector clock is represented as a map where the keys are process ID
  and the values are integers representing the event count for that process
  """
  @type t :: %{required(any()) => non_neg_integer()}

  @doc """
  Creates a new empty vector clock
  """
  # -->this is a type spec, it tells us what the function returns, like in haskell
  @spec new() :: t()
  def new() do
    %{}
  end

  @doc """
  Creates a new vector clock with a single entry for the given process
  """
  @spec new(any()) :: t()
  def new(process) do
    %{process => 0}
  end

  @doc """
  Increments the counter for the given process in the vector clock
  """
  @spec increment(t(), any()) :: t()
  def increment(clock, process) do
    # updates were key=process, if it exists, increment the value by 1, otherwise add it with a value of 1
    Map.update(clock, process, 1, fn current_value -> current_value + 1 end)
  end

  @doc """
  Merges two vector clocks by taking the maximum value for each process.
  """
  @spec merge(t(), t()) :: t()
  def merge(local_clock, remote_clock) do
    # given two vector clocks, merge them by taking the maximum value
    Map.merge(local_clock, remote_clock, fn _process, local_val, remote_val ->
      max(local_val, remote_val)
    end)
  end

  @doc """
  Compares two vector clocks to determine their causal relationship.
  Returns an atom indicating the relationship
  """
  # we want to return one of these four values
  @spec compare(t(), t()) :: :before | :after | :concurrent | :equal
  def compare(clock1, clock2) do
    all_processes = MapSet.union(MapSet.new(Map.keys(clock1)), MapSet.new(Map.keys(clock2)))

    Enum.reduce_while(all_processes, %{less: false, greater: false}, fn process, acc ->
      v1 = Map.get(clock1, process, 0)
      v2 = Map.get(clock2, process, 0)

      new_acc = %{
        less: acc.less || v1 < v2,
        greater: acc.greater || v1 > v2
      }

      # if both less and greater are true, we can stop checking
      if new_acc.less && new_acc.greater, do: {:halt, :concurrent}, else: {:cont, new_acc}
    end)
    |> case do
      :concurrent -> :concurrent
      %{less: false, greater: false} -> :equal
      %{less: true, greater: false} -> :before
      %{less: false, greater: true} -> :after
      _ -> :concurrent
    end
  end

  @doc """
  Returns true if clock1 is causally before clock2.
  """
  # helper function, it can be useful
  @spec before?(t(), t()) :: boolean()
  def before?(clock1, clock2) do
    compare(clock1, clock2) == :before
  end

  @doc """
  Returns true if clock1 is causally after clock2.
  """
  # same as above
  @spec after?(t(), t()) :: boolean()
  def after?(clock1, clock2) do
    compare(clock1, clock2) == :after
  end

  @doc """
  Returns true if the two clocks are concurrent.
  """
  # same as above
  @spec concurrent?(t(), t()) :: boolean()
  def concurrent?(clock1, clock2) do
    compare(clock1, clock2) == :concurrent
  end

  @spec equal?(t(), t()) :: boolean()
  def equal?(clock1, clock2) do
    compare(clock1, clock2) == :equal
  end
end
