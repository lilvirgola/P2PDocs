defmodule P2PDocs.CRDT.ManagerTest do
  use ExUnit.Case, async: false
  import Mox

  alias P2PDocs.CRDT.Manager

  # Hide Logger messages
  @moduletag :capture_log

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # Ensure a clean ETS table for each test
    table = :crdt_manager_state
    if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    :ets.new(table, [:named_table, :set, :public])
    :ok
  end

  describe "init/1" do
    test "creates new state when ETS is empty" do
      expect(P2PDocs.CRDT.CrdtTextMock, :new, fn "peer1" -> :crdt1 end)
      expect(P2PDocs.CRDT.AutoSaverMock, :new, fn _, "./saves/\"peer1\".txt" -> :saver1 end)

      {:ok, pid} = Manager.start_link("peer1")
      assert Process.whereis(Manager) == pid

      # verify state was inserted into ETS
      [{"peer1", %Manager{peer_id: "peer1", crdt: :crdt1, auto_saver: :saver1}}] =
        :ets.lookup(:crdt_manager_state, "peer1")
    end

    test "restores existing state from ETS" do
      pre = %Manager{peer_id: "peer2", crdt: :foo, auto_saver: :bar}
      :ets.insert(:crdt_manager_state, {"peer2", pre})

      # neither CrdtText.new nor AutoSaver.new should be called
      expect(P2PDocs.CRDT.CrdtTextMock, :new, 0, fn _ -> flunk("should not be called") end)
      expect(P2PDocs.CRDT.AutoSaverMock, :new, 0, fn _, _ -> flunk("should not be called") end)

      {:ok, _pid} = Manager.start_link("peer2")
      # call into the GenServer to verify the restored CRDT
      assert GenServer.call(Manager, :get_crdt) == :foo
    end
  end

  describe "handle_call :get_state" do
    test "returns CRDT as plain text" do
      pre = %Manager{peer_id: "p", crdt: :crdtX, auto_saver: :s}
      :ets.insert(:crdt_manager_state, {"p", pre})

      expect(P2PDocs.CRDT.CrdtTextMock, :to_plain_text, fn :crdtX -> "xyz" end)

      {:ok, _} = Manager.start_link("p")
      assert GenServer.call(Manager, :get_state) == "xyz"
    end
  end

  describe "handle_cast :local_insert" do
    test "applies insert and broadcasts" do
      pre = %Manager{peer_id: "px", crdt: :old_crdt, auto_saver: :old_saver}
      :ets.insert(:crdt_manager_state, {"px", pre})

      new_char = %{id: 1, pos: 2, value: "A"}
      new_crdt = :new_crdt
      new_saver = :new_saver

      expect(P2PDocs.CRDT.CrdtTextMock, :insert_local, fn :old_crdt, 3, "A" ->
        {new_char, new_crdt}
      end)

      expect(P2PDocs.CRDT.AutoSaverMock, :apply_op, fn :old_saver, ^new_crdt -> new_saver end)

      expect(P2PDocs.Network.CausalBroadcastMock, :broadcast, fn {:remote_insert, ^new_char} ->
        :ok
      end)

      {:ok, _} = Manager.start_link("px")
      GenServer.cast(Manager, {:local_insert, 3, "A"})
      # give it a moment to handle the cast
      :timer.sleep(10)

      [{"px", %Manager{crdt: ^new_crdt, auto_saver: ^new_saver}}] =
        :ets.lookup(:crdt_manager_state, "px")
    end
  end

  describe "handle_cast :remote_insert" do
    test "applies remote insert and notifies WebSocket" do
      pre = %Manager{peer_id: "pr", crdt: :old, auto_saver: :old_saver}
      :ets.insert(:crdt_manager_state, {"pr", pre})

      incoming = %{id: "i", pos: 5, value: "Z"}
      new_crdt = :c2
      new_saver = :s2

      expect(P2PDocs.CRDT.CrdtTextMock, :apply_remote_insert, fn :old, ^incoming ->
        {42, new_crdt}
      end)

      expect(P2PDocs.CRDT.AutoSaverMock, :apply_op, fn :old_saver, ^new_crdt -> new_saver end)
      expect(P2PDocs.API.WebSocket.HandlerMock, :remote_insert, fn 42, "Z" -> :ok end)

      {:ok, _} = Manager.start_link("pr")
      GenServer.cast(Manager, {:remote_insert, incoming})
      :timer.sleep(10)

      [{"pr", %Manager{crdt: ^new_crdt, auto_saver: ^new_saver}}] =
        :ets.lookup(:crdt_manager_state, "pr")
    end
  end

  describe "handle_cast :remote_delete" do
    test "applies remote delete and notifies WebSocket" do
      pre = %Manager{peer_id: "pd", crdt: :oldc, auto_saver: :olds}
      :ets.insert(:crdt_manager_state, {"pd", pre})

      target = {1, "x"}
      new_crdt = :c3
      new_saver = :s3

      expect(P2PDocs.CRDT.CrdtTextMock, :apply_remote_delete, fn :oldc, ^target ->
        {99, new_crdt}
      end)

      expect(P2PDocs.CRDT.AutoSaverMock, :apply_op, fn :olds, ^new_crdt -> new_saver end)
      expect(P2PDocs.API.WebSocket.HandlerMock, :remote_delete, fn 99 -> :ok end)

      {:ok, _} = Manager.start_link("pd")
      GenServer.cast(Manager, {:remote_delete, target})
      :timer.sleep(10)

      [{"pd", %Manager{crdt: ^new_crdt, auto_saver: ^new_saver}}] =
        :ets.lookup(:crdt_manager_state, "pd")
    end
  end

  describe "handle_cast :upd_crdt" do
    test "updates CRDT, applies auto‐save & sends init" do
      pre = %Manager{peer_id: "pu", crdt: :old, auto_saver: :olds}
      :ets.insert(:crdt_manager_state, {"pu", pre})

      raw_crdt = %P2PDocs.CRDT.CrdtText{}
      # Manager will wrap it into a CrdtText struct carrying peer_id
      wrapped = %P2PDocs.CRDT.CrdtText{raw_crdt | peer_id: "pu"}
      new_saver = :s4

      expect(P2PDocs.CRDT.AutoSaverMock, :apply_state_update, fn :olds, ^wrapped -> new_saver end)
      expect(P2PDocs.API.WebSocket.HandlerMock, :send_init, fn -> :ok end)

      {:ok, _} = Manager.start_link("pu")
      GenServer.cast(Manager, {:upd_crdt, raw_crdt})
      :timer.sleep(10)

      [{"pu", %Manager{crdt: ^wrapped, auto_saver: ^new_saver}}] =
        :ets.lookup(:crdt_manager_state, "pu")
    end
  end

  describe "handle_cast unknown message" do
    test "logs error and leaves state unchanged" do
      pre = %Manager{peer_id: "pxy", crdt: :orig, auto_saver: :orig_s}
      :ets.insert(:crdt_manager_state, {"pxy", pre})

      {:ok, _} = Manager.start_link("pxy")
      GenServer.cast(Manager, {:something_bad, :oops})
      :timer.sleep(10)

      [{"pxy", ^pre}] = :ets.lookup(:crdt_manager_state, "pxy")
    end
  end
end
