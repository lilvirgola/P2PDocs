defmodule P2PDocs.Network.NaiveVectorClockTest do
  use ExUnit.Case
  alias P2PDocs.Network.NaiveVectorClock

  # Hide Logger messages
  @moduletag :capture_log

  describe "new/0" do
    test "creates an empty vector clock" do
      assert NaiveVectorClock.new() == %{}
    end
  end

  describe "new/1" do
    test "creates a vector clock with a single process initialized to 0" do
      assert NaiveVectorClock.new(:process1) == %{process1: 0}
    end
  end

  describe "increment/2" do
    test "increments the counter for an existing process" do
      clock = %{process1: 1}
      assert NaiveVectorClock.increment(clock, :process1) == %{process1: 2}
    end

    test "adds a new process with a counter of 1 if it does not exist" do
      clock = %{process1: 1}
      assert NaiveVectorClock.increment(clock, :process2) == %{process1: 1, process2: 1}
    end
  end

  describe "merge/2" do
    test "merges two clocks by taking the maximum value for each process" do
      clock1 = %{process1: 2, process2: 1}
      clock2 = %{process1: 1, process3: 3}
      assert NaiveVectorClock.merge(clock1, clock2) == %{process1: 2, process2: 1, process3: 3}
    end
  end

  describe "compare/2" do
    test "returns :equal for identical clocks" do
      clock1 = %{process1: 2, process2: 1}
      clock2 = %{process1: 2, process2: 1}
      assert NaiveVectorClock.compare(clock1, clock2) == :equal
    end

    test "returns :before if clock1 is causally before clock2" do
      clock1 = %{process1: 1}
      clock2 = %{process1: 2}
      assert NaiveVectorClock.compare(clock1, clock2) == :before
    end

    test "returns :after if clock1 is causally after clock2" do
      clock1 = %{process1: 2}
      clock2 = %{process1: 1}
      assert NaiveVectorClock.compare(clock1, clock2) == :after
    end

    test "returns :concurrent if clocks are concurrent" do
      clock1 = %{process1: 1}
      clock2 = %{process2: 1}
      assert NaiveVectorClock.compare(clock1, clock2) == :concurrent
    end
  end

  describe "before?/2" do
    test "returns true if clock1 is causally before clock2" do
      clock1 = %{process1: 1}
      clock2 = %{process1: 2}
      assert NaiveVectorClock.before?(clock1, clock2)
    end

    test "returns false if clock1 is not causally before clock2" do
      clock1 = %{process1: 2}
      clock2 = %{process1: 1}
      refute NaiveVectorClock.before?(clock1, clock2)
    end
  end

  describe "after?/2" do
    test "returns true if clock1 is causally after clock2" do
      clock1 = %{process1: 2}
      clock2 = %{process1: 1}
      assert NaiveVectorClock.after?(clock1, clock2)
    end

    test "returns false if clock1 is not causally after clock2" do
      clock1 = %{process1: 1}
      clock2 = %{process1: 2}
      refute NaiveVectorClock.after?(clock1, clock2)
    end
  end

  describe "concurrent?/2" do
    test "returns true if clocks are concurrent" do
      clock1 = %{process1: 1}
      clock2 = %{process2: 1}
      assert NaiveVectorClock.concurrent?(clock1, clock2)
    end

    test "returns false if clocks are not concurrent" do
      clock1 = %{process1: 1}
      clock2 = %{process1: 2}
      refute NaiveVectorClock.concurrent?(clock1, clock2)
    end
  end
end
