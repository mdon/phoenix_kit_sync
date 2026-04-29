defmodule PhoenixKitSync.Web.ReceiverLiveTest do
  use ExUnit.Case, async: true

  # The Receiver LV requires WebSocket plumbing to a sender for any
  # mount-and-interact flow to work. The test-router doesn't wire that;
  # full sender→receiver integration is covered by
  # `test/integration/full_sync_flow_test.exs`. The pinning tests below
  # cover the helper functions that landed during the sweep.

  alias PhoenixKitSync.Web.Receiver.Helpers

  describe "Helpers (extracted in Phase 2 first-pass decomposition)" do
    test "format_strategy/1 returns user-facing strings for each conflict mode" do
      assert Helpers.format_strategy(:skip) == "Skip existing"
      assert Helpers.format_strategy(:overwrite) == "Overwrite existing"
      assert Helpers.format_strategy(:merge) == "Merge data"
      assert Helpers.format_strategy(:append) == "Append (new IDs)"
    end

    test "format_number/1 inserts thousand separators" do
      assert Helpers.format_number(1) == "1"
      assert Helpers.format_number(1_000) == "1,000"
      assert Helpers.format_number(1_234_567) == "1,234,567"
      assert Helpers.format_number(nil) == "?"
    end

    test "format_connection_error/1 unwraps WebSockex errors" do
      assert Helpers.format_connection_error({:error, :econnrefused}) =~ "Could not connect"
      assert Helpers.format_connection_error({:error, :nxdomain}) =~ "Could not find"
      assert Helpers.format_connection_error({:error, :timeout}) =~ "timed out"
      assert Helpers.format_connection_error("plain reason") == "plain reason"
    end

    test "parse_id_list/1 parses comma/space/newline-separated ids" do
      assert Helpers.parse_id_list("1, 2, 3") == [1, 2, 3]
      assert Helpers.parse_id_list("1\n2\n3") == [1, 2, 3]
      assert Helpers.parse_id_list("1 2 3") == [1, 2, 3]
      assert Helpers.parse_id_list("not a number") == []
      assert Helpers.parse_id_list("") == []
      assert Helpers.parse_id_list(nil) == []
    end

    test "get_record_id/1 prefers uuid then id, accepts string and atom keys" do
      assert Helpers.get_record_id(%{"uuid" => "abc"}) == "abc"
      assert Helpers.get_record_id(%{uuid: "abc"}) == "abc"
      assert Helpers.get_record_id(%{"id" => 7}) == 7
      assert Helpers.get_record_id(%{id: 7}) == 7
      # uuid wins when both are present
      assert Helpers.get_record_id(%{"uuid" => "abc", "id" => 7}) == "abc"
      assert Helpers.get_record_id(%{}) == nil
      assert Helpers.get_record_id(nil) == nil
    end

    test "filter_records_by_mode/2 with :ids mode keeps only matching ids" do
      records = [%{"id" => 1}, %{"id" => 2}, %{"id" => 3}]

      assert Helpers.filter_records_by_mode(records, %{mode: :ids, ids: "1, 3"}) ==
               [%{"id" => 1}, %{"id" => 3}]
    end

    test "filter_records_by_mode/2 with empty ids returns all records (no-op filter)" do
      records = [%{"id" => 1}, %{"id" => 2}]
      assert Helpers.filter_records_by_mode(records, %{mode: :ids, ids: ""}) == records
    end
  end
end
