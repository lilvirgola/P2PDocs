defmodule P2PDocs.CRDT.AutoSaver do
  @moduledoc """
  Autosave a CrdtText state to file after a set number of changes.
  """

  require Logger
  alias P2PDocs.CRDT.CrdtText

  @type t :: %__MODULE__{
          # max changes before autosave
          change_threshold: pos_integer(),
          # current change count
          change_count: non_neg_integer(),
          # destination file path
          file_path: String.t()
        }

  defstruct change_threshold: 1,
            change_count: 0,
            file_path: nil

  @doc """
  Create a new AutoSaver.

  ## Parameters
    - threshold: number of changes before autosave
    - file_path: path to write plain-text output
  """
  @callback new(threshold :: pos_integer, file_path :: binary) :: t
  @spec new(pos_integer(), String.t()) :: t()
  def new(threshold, file_path)
      when is_integer(threshold) and threshold > 0 and is_binary(file_path) do
    %__MODULE__{
      change_threshold: threshold,
      change_count: 0,
      file_path: file_path
    }
  end

  @doc """
  Apply an edit operation: increments the change count and saves if threshold reached.
  """
  @callback apply_op(auto :: t, crdt :: CrdtText.t()) :: t
  @spec apply_op(t(), CrdtText.t()) :: t()
  def apply_op(%__MODULE__{} = auto, crdt) do
    auto
    # increment change count
    |> Map.update!(:change_count, &(&1 + 1))
    # trigger save if needed
    |> maybe_save(crdt)
  end

  @doc """
  Force-save current state regardless of change count.
  """
  @callback apply_state_update(auto :: t, crdt :: CrdtText.t()) :: t
  @spec apply_state_update(t(), CrdtText.t()) :: t()
  def apply_state_update(%__MODULE__{} = auto, crdt) do
    # always write out and reset count
    save(auto, crdt)
  end

  # Internal: check threshold and save if reached
  defp maybe_save(%__MODULE__{change_count: count, change_threshold: thresh} = auto, crdt) do
    if count >= thresh do
      auto
      # reset count
      |> Map.put(:change_count, 0)
      |> save(crdt)
    else
      # no save yet
      auto
    end
  end

  # Internal: export CRDT to plain text, write to file, log on error
  defp save(%__MODULE__{file_path: path} = auto, crdt) do
    crdt
    # get list of binaries
    |> CrdtText.to_plain_text()
    # join into one string
    |> Enum.join()
    # write to file
    |> then(&File.write(path, &1))
    |> case do
      :ok ->
        # ensure count reset
        %__MODULE__{auto | change_count: 0}

      {:error, reason} ->
        Logger.error("Failed to save to #{path}: #{inspect(reason)}")
        # return original state on error
        auto
    end
  end
end
