defmodule P2PDocs.CRDT.AutoSaver do
  @moduledoc """
  Wraps a CrdtText state and auto-saves it to a file after a configured
  number of local changes, exporting its plain-text representation.

  Usage:
      auto = AutoSaver.new(crdt_state, 10, "/path/to/text.txt")
      auto = AutoSaver.insert(auto, index, value)
      auto = AutoSaver.delete(auto, index)
  """
  require Logger
  alias P2PDocs.CRDT.CrdtText

  defstruct [
    :change_threshold,
    :change_count,
    :file_path
  ]

  @type t :: %__MODULE__{
          change_threshold: pos_integer(),
          change_count: non_neg_integer(),
          file_path: String.t()
        }

  @doc """
  Initialize an AutoSaver with:
    - `threshold`: number of changes before auto-save
    - `file_path`: where to persist the plain-text output
  """
  @spec new(pos_integer(), String.t()) :: t()
  def new(threshold, file_path)
      when is_integer(threshold) and threshold > 0 and is_binary(file_path) do
    %__MODULE__{
      change_threshold: threshold,
      change_count: 0,
      file_path: file_path
    }
  end

  @spec apply_op(t(), CrdtText.t()) :: t()
  def apply_op(%__MODULE__{} = auto, crdt) do
    auto
    end
  #   new_count = auto.change_count + 1

  #   auto = %__MODULE__{auto | change_count: new_count}

  #   if new_count >= auto.change_threshold do
  #     trigger_save(auto, crdt)
  #   else
  #     auto
  #   end
  # end

  @spec apply_state_update(t(), CrdtText.t()) :: t()
  def apply_state_update(%__MODULE__{} = auto, crdt) do
    auto
    # trigger_save(auto, crdt)
  end

  # Internal: export plain text and write to file, reset counter
  defp trigger_save(%__MODULE__{} = auto, crdt) do
    case save_state(crdt, auto.file_path) do
      :ok ->
        %__MODULE__{auto | change_count: 0}

      {:error, reason} ->
        Logger.error("Auto-save to #{auto.file_path} failed: #{inspect(reason)}")
    end
  end

  @doc """
  Export the CRDT as plain text and write to `file_path`.
  Assumes `CrdtText.to_plain_text/1` returns a list of character binaries.
  """
  @spec save_state(CrdtText.t(), String.t()) :: :ok | {:error, any()}
  def save_state(crdt_state, file_path) do
    crdt_state
    |> CrdtText.to_plain_text()
    |> Enum.join()
    |> then(&File.write(file_path, &1))
  end
end
