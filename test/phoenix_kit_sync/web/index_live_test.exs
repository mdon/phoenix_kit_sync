defmodule PhoenixKitSync.Web.IndexLiveTest do
  use PhoenixKitSync.LiveCase

  describe "mount and render" do
    test "renders the sync overview dashboard", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/sync")

      # The Index LV is the entry point for the sync admin section. The
      # text content is largely fixed; the smoke test verifies mount
      # doesn't crash and the cards/explainer block render.
      assert html =~ "DB Sync"
      assert html =~ "Manage Connections"
      assert html =~ "Transfer History"
    end
  end
end
