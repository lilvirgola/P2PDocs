defmodule P2PDocs.CRDT.AutoSaver do
  @moduledoc """
  Wraps a CrdtText state and auto-saves it to a file after a configured
  number of local changes, exporting its plain-text representation.

  Usage:
      auto = AutoSaver.new(crdt_state, 10, "/path/to/text.txt")
      auto = AutoSaver.insert(auto, index, value)
      auto = AutoSaver.delete(auto, index)
  """

  alias P2PDocs.CRDT.CrdtText

  defstruct [
    :crdt,
    :change_threshold,
    :change_count,
    :file_path
  ]

    @type char_id :: {String.t(), non_neg_integer()}
  @type pos_digit :: {non_neg_integer(), String.t()}
  @type position :: [pos_digit()]
  @type crdt_char :: %{id: char_id(), pos: position(), value: binary()}

  @type t :: %__MODULE__{
          crdt: CrdtText.t(),
          change_threshold: pos_integer(),
          change_count: non_neg_integer(),
          file_path: String.t()
        }

  @doc """
  Initialize an AutoSaver with:
    - `crdt_state`: the initial CrdtText state
    - `threshold`: number of changes before auto-save
    - `file_path`: where to persist the plain-text output
  """
  @spec new(CrdtText.t(), pos_integer(), String.t()) :: t()
  def new(crdt_state, threshold, file_path)
      when is_integer(threshold) and threshold > 0 and is_binary(file_path) do
    %__MODULE__{
      crdt: crdt_state,
      change_threshold: threshold,
      change_count: 0,
      file_path: file_path
    }
  end

  @doc """
  Perform a local insert and auto-save if threshold is reached.
  """
  @spec local_insert(t(), non_neg_integer(), binary()) :: t()
  def local_insert(%__MODULE__{} = auto, index, value) do
    auto
    |> update_crdt(fn crdt -> CrdtText.insert_local(crdt, index, value) end)
  end

  @doc """
  Perform a local delete and auto-save if threshold is reached.
  """
  @spec local_delete(t(), non_neg_integer()) :: t()
  def local_delete(%__MODULE__{} = auto, index) do
    auto
    |> update_crdt(fn crdt -> CrdtText.delete_local(crdt, index) end)
  end

  @doc """
  Perform a local insert and auto-save if threshold is reached.
  """
  @spec remote_insert(t(), crdt_char()) :: {atom(), t()}
  def remote_insert(%__MODULE__{} = auto, char) do
    auto
    |> update_crdt(fn crdt -> CrdtText.apply_remote_insert(crdt, char) end)
  end

  @doc """
  Perform a local delete and auto-save if threshold is reached.
  """
  @spec remote_delete(t(), char_id()) :: {atom(), t()}
  def remote_delete(%__MODULE__{} = auto, target_id) do
    auto
    |> update_crdt(fn crdt -> CrdtText.apply_remote_delete(crdt, target_id) end)
  end

  # Internal: apply the operation, increment count, and maybe save
  defp update_crdt(%__MODULE__{} = auto, fun) do
    {_msg_to_pass, new_crdt} = fun.(auto.crdt)
    new_count = auto.change_count + 1

    auto = %__MODULE__{auto | crdt: new_crdt, change_count: new_count}

    if new_count >= auto.change_threshold do
      trigger_save(auto)
    else
      auto
    end
  end

  # Internal: export plain text and write to file, reset counter
  defp trigger_save(%__MODULE__{} = auto) do
    case save_state(auto.crdt, auto.file_path) do
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
