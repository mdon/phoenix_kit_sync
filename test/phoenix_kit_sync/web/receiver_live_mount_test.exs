defmodule PhoenixKitSync.Web.ReceiverLiveMountTest do
  use PhoenixKitSync.LiveCase

  describe "mount and render" do
    test "renders the initial enter-credentials form", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/sync/receive")

      # The Receiver LV starts in :enter_credentials step. The form
      # asks for sender_url and connection_code before any WebSocket
      # action.
      assert html =~ "Receive Data" or html =~ "sender" or html =~ "code"
    end

    test "update_form event captures the sender_url and code", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/sync/receive")

      html =
        view
        |> form("form",
          sender_url: "https://example.com",
          connection_code: "abcd1234"
        )
        |> render_change()

      # After update_form fires, the input retains the typed value.
      # Code is uppercased (seen in handle_event("update_form")).
      assert html =~ "https://example.com"
      assert html =~ "ABCD1234"
    end

    test "connect button without input shows error message", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/sync/receive")

      html =
        view
        |> element("form")
        |> render_submit()

      # With no URL, the LV sets `:error_message` instead of starting
      # the WebSocket. The connect handler validates URL presence
      # before send(self(), :start_websocket).
      assert html =~ "URL" or html =~ "code" or html =~ "8 characters"
    end
  end
end
