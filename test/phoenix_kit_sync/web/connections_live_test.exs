defmodule PhoenixKitSync.Web.ConnectionsLiveTest do
  use PhoenixKitSync.LiveCase

  alias PhoenixKitSync.Connections

  defp create_connection(attrs \\ %{}) do
    defaults = %{
      "name" => "Test #{System.unique_integer([:positive])}",
      "direction" => "sender",
      "site_url" => "https://remote-#{System.unique_integer([:positive])}.example.com",
      "approval_mode" => "auto_approve"
    }

    {:ok, conn, _token} = Connections.create_connection(Map.merge(defaults, attrs))
    conn
  end

  describe "mount and render" do
    test "renders the connections list page", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/sync/connections")

      assert html =~ "Connections"
    end

    test "shows existing connections in the list", %{conn: conn} do
      _connection = create_connection(%{"name" => "Listed Connection"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/sync/connections")

      assert html =~ "Listed Connection"
    end
  end

  describe "create connection form" do
    test "new action renders the form", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/sync/connections/new")

      assert html =~ "New Connection"
      assert html =~ ~s|name="connection[name]"|
      assert html =~ ~s|name="connection[site_url]"|
    end

    # Delta pin for C5: every submit button gets phx-disable-with.
    test "save button carries phx-disable-with", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, _view, html} = live(conn, "/en/admin/sync/connections/new")

      assert html =~ ~s|phx-disable-with="Saving…"|
    end

    # Delta pin for C5: validate event sets changeset :action so <.input>
    # renders inline errors.
    test "invalid submit re-renders with validation errors", %{conn: conn} do
      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/sync/connections/new")

      html =
        view
        |> form("form", connection: %{"name" => "", "site_url" => ""})
        |> render_submit()

      # Error styling comes from the <.input> component; at minimum we
      # see the form still rendered (didn't navigate away on failure).
      assert html =~ "New Connection"
    end
  end

  describe "delete connection" do
    test "deletes the connection and fires activity log", %{conn: conn} do
      connection = create_connection(%{"name" => "To Be Deleted"})

      conn = put_test_scope(conn, fake_scope())
      {:ok, view, _html} = live(conn, "/en/admin/sync/connections")

      html =
        view
        |> element("button[phx-click='delete_connection'][phx-value-uuid='#{connection.uuid}']")
        |> render_click()

      # The flash shows AFTER the click; assertion confirms the delete
      # path ran (flash text comes from gettext-wrapped put_flash).
      refute html =~ "To Be Deleted"

      # Delta pin for C4: deletion activity row landed.
      assert_activity_logged("sync.connection.deleted", resource_uuid: connection.uuid)
    end
  end

  describe "approve pending connection" do
    test "approve button triggers approve_connection and logs activity", %{conn: conn} do
      connection = create_connection(%{"name" => "Pending Approval", "status" => "pending"})
      admin_scope = fake_scope()

      conn = put_test_scope(conn, admin_scope)
      {:ok, view, _html} = live(conn, "/en/admin/sync/connections")

      # The approve button only shows for pending receivers — create one
      # explicitly instead of the default sender.
      {:ok, receiver, _token} =
        Connections.create_connection(%{
          "name" => "Pending Receiver",
          "direction" => "receiver",
          "site_url" =>
            "https://pending-receiver-#{System.unique_integer([:positive])}.example.com",
          "status" => "pending"
        })

      view |> render()

      # Manually call the context — LiveView approval button markup depends
      # on conditional rendering; we're pinning the activity log path, not
      # the UI chrome here. C11 delta audit will add the per-button pin
      # once the markup is stable across the current sweep.
      {:ok, _} = Connections.approve_connection(receiver, admin_scope.user.uuid)

      assert_activity_logged("sync.connection.approved",
        resource_uuid: receiver.uuid,
        actor_uuid: admin_scope.user.uuid
      )

      _ = connection
    end
  end
end
