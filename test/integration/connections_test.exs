defmodule PhoenixKitSync.Integration.ConnectionsTest do
  use PhoenixKitSync.DataCase, async: false

  import PhoenixKitSync.ActivityLogAssertions

  alias PhoenixKitSync.Connections

  @valid_attrs %{
    "name" => "Test Sender",
    "direction" => "sender",
    "site_url" => "https://remote.example.com",
    "approval_mode" => "auto_approve"
  }

  defp create_connection(attrs \\ %{}) do
    merged = Map.merge(@valid_attrs, attrs)
    {:ok, conn, _token} = Connections.create_connection(merged)
    conn
  end

  # ===========================================
  # CREATE
  # ===========================================

  describe "create_connection/1" do
    test "creates a connection with valid attrs" do
      assert {:ok, conn, _token} = Connections.create_connection(@valid_attrs)
      assert conn.name == "Test Sender"
      assert conn.direction == "sender"
      assert conn.site_url == "https://remote.example.com"
      assert conn.status == "pending"
    end

    test "generates and returns auth token" do
      assert {:ok, conn, token} = Connections.create_connection(@valid_attrs)
      assert is_binary(token)
      assert conn.auth_token_hash != nil
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Connections.create_connection(%{})
      errors = errors_on(changeset)
      assert errors[:name] != nil
      assert errors[:direction] != nil
      assert errors[:site_url] != nil
    end

    test "enforces unique (site_url, direction) constraint" do
      _first = create_connection()

      assert {:error, changeset} = Connections.create_connection(@valid_attrs)
      errors = errors_on(changeset)
      assert errors[:site_url] != nil or errors[:direction] != nil
    end
  end

  # ===========================================
  # READ
  # ===========================================

  describe "get_connection/1" do
    test "returns connection by uuid" do
      conn = create_connection()
      found = Connections.get_connection(conn.uuid)
      assert found != nil
      assert found.uuid == conn.uuid
    end

    test "returns nil for non-existent uuid" do
      assert Connections.get_connection(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_connections/1" do
    test "returns all connections" do
      _conn1 = create_connection(%{"site_url" => "https://site1.com", "direction" => "sender"})
      _conn2 = create_connection(%{"site_url" => "https://site2.com", "direction" => "sender"})
      connections = Connections.list_connections()
      assert length(connections) >= 2
    end

    test "filters by direction" do
      _sender = create_connection(%{"site_url" => "https://s.com", "direction" => "sender"})
      _receiver = create_connection(%{"site_url" => "https://r.com", "direction" => "receiver"})

      senders = Connections.list_connections(direction: "sender")
      assert Enum.all?(senders, &(&1.direction == "sender"))
    end

    test "filters by status" do
      conn = create_connection(%{"site_url" => "https://status-test.com"})
      Connections.approve_connection(conn, UUIDv7.generate())

      active = Connections.list_connections(status: "active")
      assert Enum.all?(active, &(&1.status == "active"))
    end
  end

  # ===========================================
  # STATUS TRANSITIONS
  # ===========================================

  describe "approve_connection/2" do
    test "transitions pending to active" do
      conn = create_connection()
      assert conn.status == "pending"

      admin_uuid = UUIDv7.generate()
      assert {:ok, approved} = Connections.approve_connection(conn, admin_uuid)
      assert approved.status == "active"
      assert approved.approved_at != nil
      assert approved.approved_by_uuid == admin_uuid
    end
  end

  describe "suspend_connection/3" do
    test "transitions active to suspended" do
      conn = create_connection()
      {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())

      assert {:ok, suspended} =
               Connections.suspend_connection(active, UUIDv7.generate(), "Security review")

      assert suspended.status == "suspended"
      assert suspended.suspended_reason == "Security review"
    end
  end

  describe "reactivate_connection/1" do
    test "transitions suspended back to active" do
      conn = create_connection()
      {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())
      {:ok, suspended} = Connections.suspend_connection(active, UUIDv7.generate(), "temp")

      assert {:ok, reactivated} = Connections.reactivate_connection(suspended)
      assert reactivated.status == "active"
      assert reactivated.suspended_at == nil
      assert reactivated.suspended_reason == nil
    end
  end

  describe "revoke_connection/3" do
    test "transitions to revoked" do
      conn = create_connection()
      {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())

      assert {:ok, revoked} =
               Connections.revoke_connection(active, UUIDv7.generate(), "Decommissioned")

      assert revoked.status == "revoked"
      assert revoked.revoked_reason == "Decommissioned"
    end
  end

  # ===========================================
  # TOKEN VALIDATION
  # ===========================================

  describe "validate_connection/2" do
    test "validates active connection with correct token" do
      merged =
        Map.merge(@valid_attrs, %{
          "site_url" => "https://validate-test.com",
          "ip_whitelist" => ["127.0.0.1"]
        })

      {:ok, conn, token} = Connections.create_connection(merged)
      {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())

      assert {:ok, validated} = Connections.validate_connection(token, "127.0.0.1")
      assert validated.uuid == active.uuid
    end

    test "rejects invalid token" do
      assert {:error, :invalid_token} = Connections.validate_connection("bogus-token")
    end

    test "rejects non-active connection" do
      merged = Map.merge(@valid_attrs, %{"site_url" => "https://pending-test.com"})
      {:ok, _conn, token} = Connections.create_connection(merged)
      # Connection is still "pending"
      assert {:error, :connection_not_active} = Connections.validate_connection(token)
    end

    test "rejects expired connection" do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, conn, token} =
        Connections.create_connection(
          Map.merge(@valid_attrs, %{"site_url" => "https://expired.com", "expires_at" => past})
        )

      {:ok, _active} = Connections.approve_connection(conn, UUIDv7.generate())
      assert {:error, :connection_expired} = Connections.validate_connection(token)
    end
  end

  # ===========================================
  # DELETE
  # ===========================================

  describe "delete_connection/1" do
    test "deletes a connection" do
      conn = create_connection()
      assert {:ok, _} = Connections.delete_connection(conn)
      assert Connections.get_connection(conn.uuid) == nil
    end
  end

  # ===========================================
  # UPDATE
  # ===========================================

  describe "update_connection/2" do
    test "updates connection settings" do
      conn = create_connection()

      assert {:ok, updated} =
               Connections.update_connection(conn, %{
                 name: "Updated Name",
                 max_downloads: 100
               })

      assert updated.name == "Updated Name"
      assert updated.max_downloads == 100
    end

    test "validates on update" do
      conn = create_connection()

      assert {:error, changeset} =
               Connections.update_connection(conn, %{max_records_per_request: -5})

      errors = errors_on(changeset)
      assert errors[:max_records_per_request] != nil
    end
  end

  # ===========================================
  # VALIDATE EDGE CASES
  # ===========================================

  describe "validate_connection edge cases" do
    test "rejects connection when download limit is reached" do
      merged =
        Map.merge(@valid_attrs, %{
          "site_url" => "https://dl-limit-#{System.unique_integer([:positive])}.com",
          "max_downloads" => 5
        })

      {:ok, conn, token} = Connections.create_connection(merged)
      {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())

      # Set downloads_used to exceed max_downloads
      {:ok, _exhausted} =
        Connections.update_connection(active, %{downloads_used: 5})

      assert {:error, :download_limit_reached} = Connections.validate_connection(token)
    end

    test "rejects connection when record limit is reached" do
      merged =
        Map.merge(@valid_attrs, %{
          "site_url" => "https://rec-limit-#{System.unique_integer([:positive])}.com",
          "max_records_total" => 1000
        })

      {:ok, conn, token} = Connections.create_connection(merged)
      {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())

      # Set records_downloaded to exceed max_records_total
      {:ok, _exhausted} =
        Connections.update_connection(active, %{records_downloaded: 1000})

      assert {:error, :record_limit_reached} = Connections.validate_connection(token)
    end
  end

  # ===========================================
  # COUNT
  # ===========================================

  describe "count_connections/1" do
    test "returns count of all connections" do
      _conn1 = create_connection(%{"site_url" => "https://count1.com", "direction" => "sender"})
      _conn2 = create_connection(%{"site_url" => "https://count2.com", "direction" => "sender"})

      assert Connections.count_connections() >= 2
    end

    test "returns count matching direction filter" do
      _sender = create_connection(%{"site_url" => "https://cs.com", "direction" => "sender"})
      _receiver = create_connection(%{"site_url" => "https://cr.com", "direction" => "receiver"})

      sender_count = Connections.count_connections(direction: "sender")
      assert sender_count >= 1

      receiver_count = Connections.count_connections(direction: "receiver")
      assert receiver_count >= 1
    end

    test "returns count matching status filter" do
      conn = create_connection(%{"site_url" => "https://cstatus.com"})
      Connections.approve_connection(conn, UUIDv7.generate())

      active_count = Connections.count_connections(status: "active")
      assert active_count >= 1

      pending_count = Connections.count_connections(status: "pending")
      assert is_integer(pending_count)
    end
  end

  # ===========================================
  # SELF-CONNECTION PROTECTION
  # ===========================================

  describe "self-connection protection" do
    test "allows sender to different site" do
      result =
        Connections.create_connection(%{
          "name" => "Different Site",
          "direction" => "sender",
          "site_url" =>
            "https://completely-different-site-#{System.unique_integer([:positive])}.example.com"
        })

      assert {:ok, _conn, _token} = result
    end

    test "allows receiver even if site_url matches own (API-created)" do
      # Receivers are created by remote API — should never be blocked
      # Use a URL that would match our own if self-check ran
      result =
        Connections.create_connection(%{
          "name" => "From: Remote",
          "direction" => "receiver",
          "site_url" => "https://self-check-receiver-#{System.unique_integer([:positive])}.com"
        })

      assert {:ok, conn, _token} = result
      assert conn.direction == "receiver"
    end

    test "self-connection check does not crash when Settings table is missing" do
      # In test env, phoenix_kit_settings doesn't exist.
      # create_connection should rescue and allow the connection through
      # (the self-check returns false on error, so it doesn't block)
      result =
        Connections.create_connection(%{
          "name" => "Resilient Test",
          "direction" => "sender",
          "site_url" => "https://resilient-#{System.unique_integer([:positive])}.com"
        })

      assert {:ok, _conn, _token} = result
    end
  end

  # ===========================================
  # PUBSUB BROADCASTS
  # ===========================================

  describe "PubSub broadcasts" do
    setup do
      pubsub = PhoenixKit.Config.pubsub_server()
      Phoenix.PubSub.subscribe(pubsub, "sync:connections")
      :ok
    end

    test "create_connection broadcasts :connection_created" do
      {:ok, conn, _token} =
        Connections.create_connection(%{
          "name" => "PubSub Create Test",
          "direction" => "sender",
          "site_url" => "https://pubsub-create-#{System.unique_integer([:positive])}.com"
        })

      assert_receive {:connection_created, uuid}
      assert uuid == conn.uuid
    end

    test "delete_connection broadcasts :connection_deleted" do
      conn =
        create_connection(%{
          "site_url" => "https://pubsub-delete-#{System.unique_integer([:positive])}.com"
        })

      # Drain the create broadcast
      assert_receive {:connection_created, _}

      {:ok, _} = Connections.delete_connection(conn)
      assert_receive {:connection_deleted, uuid}
      assert uuid == conn.uuid
    end

    test "approve_connection broadcasts :connection_status_changed" do
      conn =
        create_connection(%{
          "site_url" => "https://pubsub-approve-#{System.unique_integer([:positive])}.com"
        })

      assert_receive {:connection_created, _}

      {:ok, _} = Connections.approve_connection(conn, UUIDv7.generate())
      assert_receive {:connection_status_changed, uuid, "active"}
      assert uuid == conn.uuid
    end

    test "suspend_connection broadcasts :connection_status_changed" do
      conn =
        create_connection(%{
          "site_url" => "https://pubsub-suspend-#{System.unique_integer([:positive])}.com"
        })

      assert_receive {:connection_created, _}
      {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())
      assert_receive {:connection_status_changed, _, "active"}

      {:ok, _} = Connections.suspend_connection(active, UUIDv7.generate(), "test")
      assert_receive {:connection_status_changed, uuid, "suspended"}
      assert uuid == conn.uuid
    end

    test "revoke_connection broadcasts :connection_status_changed" do
      conn =
        create_connection(%{
          "site_url" => "https://pubsub-revoke-#{System.unique_integer([:positive])}.com"
        })

      assert_receive {:connection_created, _}
      {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())
      assert_receive {:connection_status_changed, _, "active"}

      {:ok, _} = Connections.revoke_connection(active, UUIDv7.generate(), "test")
      assert_receive {:connection_status_changed, uuid, "revoked"}
      assert uuid == conn.uuid
    end

    test "reactivate_connection broadcasts :connection_status_changed" do
      conn =
        create_connection(%{
          "site_url" => "https://pubsub-react-#{System.unique_integer([:positive])}.com"
        })

      assert_receive {:connection_created, _}
      {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())
      assert_receive {:connection_status_changed, _, "active"}
      {:ok, suspended} = Connections.suspend_connection(active, UUIDv7.generate())
      assert_receive {:connection_status_changed, _, "suspended"}

      {:ok, _} = Connections.reactivate_connection(suspended)
      assert_receive {:connection_status_changed, uuid, "active"}
      assert uuid == conn.uuid
    end

    test "update_connection with status change broadcasts :connection_status_changed" do
      conn =
        create_connection(%{
          "site_url" => "https://pubsub-update-#{System.unique_integer([:positive])}.com"
        })

      assert_receive {:connection_created, _}

      {:ok, _} = Connections.update_connection(conn, %{status: "active"})
      assert_receive {:connection_status_changed, uuid, "active"}
      assert uuid == conn.uuid
    end

    test "update_connection without status change broadcasts :connection_updated" do
      conn =
        create_connection(%{
          "site_url" => "https://pubsub-update2-#{System.unique_integer([:positive])}.com"
        })

      assert_receive {:connection_created, _}

      {:ok, _} = Connections.update_connection(conn, %{name: "Updated Name"})
      assert_receive {:connection_updated, uuid}
      assert uuid == conn.uuid
    end

    # Regression: string-keyed attrs (e.g. from a LiveView form) used to make
    # every field look "changed" because Map.get(%Connection{}, "status")
    # always returned nil, never matching the string-keyed value. That
    # incorrectly fired :connection_updated on no-op saves and routed real
    # status changes to :connection_updated instead of :connection_status_changed.
    test "update_connection with string-keyed status attr fires :connection_status_changed" do
      conn =
        create_connection(%{
          "site_url" => "https://pubsub-string-status-#{System.unique_integer([:positive])}.com"
        })

      assert_receive {:connection_created, _}

      {:ok, _} = Connections.update_connection(conn, %{"status" => "active"})
      assert_receive {:connection_status_changed, uuid, "active"}
      assert uuid == conn.uuid

      refute_receive {:connection_updated, _}, 50
    end

    test "update_connection with no actual change emits no stale broadcast" do
      conn =
        create_connection(%{
          "name" => "No-op Name",
          "site_url" => "https://pubsub-noop-#{System.unique_integer([:positive])}.com"
        })

      assert_receive {:connection_created, _}

      # Submit the same name via a string-keyed attr map. Before the
      # atom-key normalization fix this would broadcast :connection_updated
      # because the comparison mis-read the struct.
      {:ok, _} = Connections.update_connection(conn, %{"name" => "No-op Name"})

      refute_receive {:connection_updated, _}, 50
      refute_receive {:connection_status_changed, _, _}, 50
    end
  end

  describe "activity logging" do
    # Pinning tests for the C4 audit trail. Each mutation should persist a
    # `sync.connection.<verb>` row into phoenix_kit_activities with the
    # connection's uuid as resource_uuid and a safe metadata subset
    # (name/direction/status — never site_url or auth fields).

    test "create_connection logs sync.connection.created" do
      conn =
        create_connection(%{
          "site_url" => "https://act-create-#{System.unique_integer([:positive])}.com"
        })

      assert_activity_logged("sync.connection.created",
        resource_uuid: conn.uuid,
        metadata_has: %{
          "connection_name" => conn.name,
          "direction" => "sender",
          "status" => "pending"
        }
      )
    end

    test "approve_connection logs sync.connection.approved with actor_uuid" do
      conn =
        create_connection(%{
          "site_url" => "https://act-approve-#{System.unique_integer([:positive])}.com"
        })

      admin_uuid = UUIDv7.generate()
      {:ok, _} = Connections.approve_connection(conn, admin_uuid)

      assert_activity_logged("sync.connection.approved",
        resource_uuid: conn.uuid,
        actor_uuid: admin_uuid
      )
    end

    test "suspend_connection logs sync.connection.suspended with reason" do
      conn =
        create_connection(%{
          "site_url" => "https://act-suspend-#{System.unique_integer([:positive])}.com"
        })

      admin_uuid = UUIDv7.generate()
      {:ok, _} = Connections.suspend_connection(conn, admin_uuid, "Security audit")

      assert_activity_logged("sync.connection.suspended",
        resource_uuid: conn.uuid,
        actor_uuid: admin_uuid,
        metadata_has: %{"reason" => "Security audit"}
      )
    end

    test "revoke_connection logs sync.connection.revoked with reason" do
      conn =
        create_connection(%{
          "site_url" => "https://act-revoke-#{System.unique_integer([:positive])}.com"
        })

      admin_uuid = UUIDv7.generate()
      {:ok, _} = Connections.revoke_connection(conn, admin_uuid, "Compromised")

      assert_activity_logged("sync.connection.revoked",
        resource_uuid: conn.uuid,
        actor_uuid: admin_uuid,
        metadata_has: %{"reason" => "Compromised"}
      )
    end

    test "reactivate_connection logs sync.connection.reactivated with actor opt" do
      conn =
        create_connection(%{
          "site_url" => "https://act-reactivate-#{System.unique_integer([:positive])}.com"
        })

      admin_uuid = UUIDv7.generate()
      {:ok, suspended} = Connections.suspend_connection(conn, admin_uuid)
      {:ok, _} = Connections.reactivate_connection(suspended, actor_uuid: admin_uuid)

      assert_activity_logged("sync.connection.reactivated",
        resource_uuid: conn.uuid,
        actor_uuid: admin_uuid
      )
    end

    test "delete_connection logs sync.connection.deleted with actor via opts" do
      conn =
        create_connection(%{
          "site_url" => "https://act-delete-#{System.unique_integer([:positive])}.com"
        })

      admin_uuid = UUIDv7.generate()
      {:ok, _} = Connections.delete_connection(conn, actor_uuid: admin_uuid)

      assert_activity_logged("sync.connection.deleted",
        resource_uuid: conn.uuid,
        actor_uuid: admin_uuid
      )
    end

    test "metadata never leaks site_url or auth_token_hash" do
      conn =
        create_connection(%{
          "site_url" => "https://act-leak-check-#{System.unique_integer([:positive])}.com"
        })

      created = assert_activity_logged("sync.connection.created", resource_uuid: conn.uuid)
      metadata = created.metadata || %{}
      refute Map.has_key?(metadata, "site_url")
      refute Map.has_key?(metadata, "auth_token_hash")
      refute Map.has_key?(metadata, "auth_token")
    end
  end
end
