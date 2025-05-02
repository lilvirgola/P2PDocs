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
  @type t :: %{required(any()) => non_neg_integer()} #map something (in our case a process ID) to a non neg event count

  @doc """
  Creates a new empty vector clock
  """
  @spec new() :: t() #-->this is a type spec, it tells us what the function returns, like in haskell
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
    Map.update(clock, process, 1, fn current_value -> current_value + 1 end) #updates were key=process, if it exists, increment the value by 1, otherwise add it with a value of 1
  end

  @doc """
  Merges two vector clocks by taking the maximum value for each process.
  """
  @spec merge(t(), t()) :: t()
  def merge(local_clock, remote_clock) do
    #given two vector clocks, merge them by taking the maximum value
    Map.merge(local_clock, remote_clock, fn _process, local_val, remote_val ->
      max(local_val, remote_val)
    end)
  end

  @doc """
  Compares two vector clocks to determine their causal relationship.
  Returns an atom indicating the relationship
  """
  @spec compare(t(), t()) :: :before | :after | :concurrent | :equal #we want to return one of these four values
  def compare(clock1, clock2) do
    all_processes = MapSet.union(MapSet.new(Map.keys(clock1)), MapSet.new(Map.keys(clock2))) #get all unique processes from both clocks

    #initialize comparison flags
    results =
      Enum.reduce(all_processes, %{less: false, greater: false, equal: true}, fn process, acc -> #for the process in both the clock, get its value (default to 0 if it doesn't exist) and compare them

        v1 = Map.get(clock1, process, 0)
        v2 = Map.get(clock2, process, 0)

        %{
          less: acc.less || v1 < v2,
          greater: acc.greater || v1 > v2,
          equal: acc.equal && v1 == v2
        }
      end)
    # Determine the relationship based on the flags
    # If both less and greater are true, they are concurrent
    # If equal is true, they are equal
    # If less is true and greater is false, clock1 is before clock2
    # If greater is true and less is false, clock1 is after clock2
    # If both less and greater are false, they are concurrent
    cond do
      results.equal -> :equal
      !results.greater -> :before
      !results.less -> :after
      true -> :concurrent
    end
  end

  @doc """
  Returns true if clock1 is causally before clock2.
  """
  @spec before?(t(), t()) :: boolean() #helper function, it can be useful
  def before?(clock1, clock2) do
    compare(clock1, clock2) == :before
  end

  @doc """
  Returns true if clock1 is causally after clock2.
  """
  @spec after?(t(), t()) :: boolean() #same as above
  def after?(clock1, clock2) do
    compare(clock1, clock2) == :after
  end

  @doc """
  Returns true if the two clocks are concurrent.
  """
  @spec concurrent?(t(), t()) :: boolean() #same as above
  def concurrent?(clock1, clock2) do
    compare(clock1, clock2) == :concurrent
  end

end
