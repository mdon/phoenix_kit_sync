defmodule PhoenixKitSync.Integration.ConnectionNotifierTest do
  use PhoenixKitSync.DataCase, async: false

  alias PhoenixKitSync.ConnectionNotifier
  alias PhoenixKitSync.Connections

  # Tests for the cross-site HTTP client. Uses our own Test.Endpoint
  # (which exposes ApiController under /sync/api/*) as the "remote
  # site" — ConnectionNotifier calls localhost:test_port and gets real
  # responses from the same ApiController code production calls.

  defp test_url do
    port = Application.fetch_env!(:phoenix_kit_sync, :test_endpoint_port)
    "http://localhost:#{port}"
  end

  defp create_sender_connection(attrs \\ %{}) do
    defaults = %{
      "name" => "Notifier Test #{System.unique_integer([:positive])}",
      "direction" => "sender",
      "site_url" =>
        Map.get(attrs, "site_url") ||
          test_url() <> "?id=#{System.unique_integer([:positive])}",
      "approval_mode" => "auto_approve"
    }

    {:ok, conn, token} = Connections.create_connection(Map.merge(defaults, attrs))
    {conn, token}
  end

  setup do
    PhoenixKitSync.enable_system()
    PhoenixKitSync.set_incoming_password(nil)
    PhoenixKitSync.set_incoming_mode("auto_accept")

    # The notifier's get_our_site_url/0 reads from Settings; default to
    # something distinct from the test endpoint so self-connection
    # rejection doesn't interfere.
    PhoenixKit.Settings.update_setting("site_url", "http://our-test-site.example")

    :ok
  end

  describe "notify_remote_site/3 — register at the mock remote" do
    test "successfully registers and records remote_connection_uuid" do
      {connection, token} = create_sender_connection(%{"site_url" => test_url()})

      assert {:ok, result} = ConnectionNotifier.notify_remote_site(connection, token)
      assert result.success == true
      assert result.status == :registered
      assert is_binary(result.remote_connection_uuid)
    end

    test "skipped when direction is not sender" do
      {receiver, _token} = create_sender_connection(%{"direction" => "receiver"})

      {:ok, result} = ConnectionNotifier.notify_remote_site(receiver, "anything")
      assert result.status == :skipped
      assert result.success == true
    end

    test "records :failed when remote rejects with module disabled" do
      {connection, token} = create_sender_connection(%{"site_url" => test_url()})

      PhoenixKitSync.disable_system()

      {:ok, result} = ConnectionNotifier.notify_remote_site(connection, token)
      assert result.success == false
      assert result.http_status == 503

      PhoenixKitSync.enable_system()
    end
  end

  describe "check_remote_status/1" do
    test "returns the remote site's status payload" do
      {:ok, body} = ConnectionNotifier.check_remote_status(test_url())
      assert is_map(body)
      assert body["enabled"] == true
    end

    test "returns {:error, _} for unreachable host" do
      assert {:error, _} = ConnectionNotifier.check_remote_status("http://nope.local.invalid:1")
    end
  end

  describe "notify_delete/2 — remote delete flow" do
    test "deletes the connection on the remote site" do
      # Step 1: register a connection on the mock remote so there's
      # something to delete.
      {connection, token} = create_sender_connection(%{"site_url" => test_url()})
      {:ok, %{success: true}} = ConnectionNotifier.notify_remote_site(connection, token)

      # Reload to pick up auth_token_hash + metadata.
      connection = Connections.get_connection!(connection.uuid)

      # Step 2: notify the remote to delete.
      assert {:ok, :deleted} = ConnectionNotifier.notify_delete(connection)
    end

    test "returns {:error, :missing_connection_info} when site_url is nil" do
      stub = %{site_url: nil, auth_token_hash: "irrelevant"}
      assert {:error, :missing_connection_info} = ConnectionNotifier.notify_delete(stub)
    end
  end

  describe "query_sender_status/1" do
    test "returns {:ok, status} for a known sender connection" do
      {connection, token} = create_sender_connection(%{"site_url" => test_url()})
      {:ok, _} = ConnectionNotifier.notify_remote_site(connection, token)

      # The remote (us) created a paired sender connection in its
      # local DB; query_sender_status hits its
      # /get-connection-status endpoint.
      connection = Connections.get_connection!(connection.uuid)
      result = ConnectionNotifier.query_sender_status(connection)

      assert match?({:ok, _}, result)
    end

    test "returns {:ok, :offline} for an unreachable site" do
      stub = %{site_url: "http://unreachable.invalid", auth_token_hash: "x"}
      assert {:ok, :offline} = ConnectionNotifier.query_sender_status(stub)
    end
  end

  describe "verify_connection/1" do
    test "returns :ok for a registered connection" do
      {connection, token} = create_sender_connection(%{"site_url" => test_url()})
      {:ok, _} = ConnectionNotifier.notify_remote_site(connection, token)

      connection = Connections.get_connection!(connection.uuid)
      result = ConnectionNotifier.verify_connection(connection)
      assert match?({:ok, _}, result)
    end

    test "returns {:ok, :offline} for an unreachable site" do
      stub = %{site_url: "http://unreachable.invalid", auth_token_hash: "x"}
      assert {:ok, :offline} = ConnectionNotifier.verify_connection(stub)
    end
  end
end
