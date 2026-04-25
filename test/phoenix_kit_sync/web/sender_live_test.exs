defmodule PhoenixKitSync.Web.SenderLiveTest do
  use PhoenixKitSync.LiveCase

  describe "mount and render" do
    test "renders the initial generate-code form", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/sync/send")

      # The Sender LV starts in the :generate_code step. Render shows
      # the page title and the generate button.
      assert html =~ "Send Data" or html =~ "Generate"
    end
  end

  describe "PID → UUIDv7 token refactor pinning (PR #1 fix)" do
    # The fix: `string_to_pid/1` and `pid_to_string/1` were deleted; the
    # disconnect button now carries `phx-value-token` keyed to a stable
    # `UUIDv7.generate()` token stored inside `receiver_data`.
    test "string_to_pid / pid_to_string are no longer defined on Sender" do
      refute function_exported?(PhoenixKitSync.Web.Sender, :string_to_pid, 1)
      refute function_exported?(PhoenixKitSync.Web.Sender, :pid_to_string, 1)
    end
  end
end
