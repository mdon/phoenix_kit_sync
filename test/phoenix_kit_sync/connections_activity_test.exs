defmodule PhoenixKitSync.ConnectionsActivityTest do
  @moduledoc """
  Pins the Batch 3 activity-logging deltas:
  - `update_connection/3` logs on BOTH `:ok` and `:error` branches
    (was unlogged on either before this batch).
  - `:error`-branch logging on the five status mutations
    (`delete_connection`, `approve_connection`, `suspend_connection`,
    `revoke_connection`, `reactivate_connection`). These branches are
    rarely reachable via the public API path (changesets use `change/2`
    with put_change, and DB-side failures surface as `Ecto.StaleEntryError`
    raises rather than `{:error, _}` tuples) so the runtime pins target
    `update_connection/3` and the others get structural source pins.

  Activity rows on `:error` carry `"db_pending": true` so the audit
  trail still records the user-initiated intent even though the DB
  write failed — analytics queries that filter on `action` see the
  attempt, not just successes.
  """

  use PhoenixKitSync.LiveCase

  alias PhoenixKitSync.Connections
  alias PhoenixKitSync.Test.Repo, as: TestRepo

  describe "update_connection/3 — :ok branch logs" do
    test "writes a sync.connection.updated row with changed_fields metadata" do
      connection = create_active_sender_connection()
      actor_uuid = UUIDv7.generate()

      {:ok, _updated} =
        Connections.update_connection(
          connection,
          %{"max_records_per_request" => 5000},
          actor_uuid: actor_uuid
        )

      assert_activity_logged("sync.connection.updated",
        resource_uuid: connection.uuid,
        actor_uuid: actor_uuid
      )

      # Metadata captures which fields changed (names only; never values
      # — `download_password` and free-text fields stay out).
      activity = latest_activity_for(connection.uuid)
      assert "max_records_per_request" in activity.metadata["changed_fields"]
      refute Map.has_key?(activity.metadata, "db_pending")
    end

    test "actor_uuid: nil is recorded for system-initiated updates" do
      connection = create_active_sender_connection()

      {:ok, _updated} =
        Connections.update_connection(connection, %{"max_records_per_request" => 7000})

      assert_activity_logged("sync.connection.updated",
        resource_uuid: connection.uuid
      )

      activity = latest_activity_for(connection.uuid)
      assert is_nil(activity.actor_uuid)
    end
  end

  describe "update_connection/3 — :error branch logs" do
    test "writes a sync.connection.updated row with db_pending: true on validation failure" do
      connection = create_active_sender_connection()
      actor_uuid = UUIDv7.generate()

      # `validate_number(:max_records_per_request, greater_than: 0)` rejects
      # this — the changeset returns `{:error, %Ecto.Changeset{}}` and the
      # error-branch logger fires.
      assert {:error, %Ecto.Changeset{}} =
               Connections.update_connection(
                 connection,
                 %{"max_records_per_request" => -1},
                 actor_uuid: actor_uuid
               )

      assert_activity_logged("sync.connection.updated",
        resource_uuid: connection.uuid,
        actor_uuid: actor_uuid
      )

      activity = latest_activity_for(connection.uuid)
      assert activity.metadata["db_pending"] == true
      assert "max_records_per_request" in activity.metadata["changed_fields"]
    end
  end

  describe "structural pins on the five status-mutation :error branches" do
    test "delete_connection logs on :error" do
      source = File.read!("lib/phoenix_kit_sync/connections.ex")

      assert source =~
               ~r/case repo\.delete\(connection\) do[\s\S]+?error ->\s+log_sync_activity\("deleted", connection, opts, %\{"db_pending" => true\}\)/,
             "delete_connection :error branch must call log_sync_activity with db_pending: true"
    end

    test "approve_connection logs on :error" do
      source = File.read!("lib/phoenix_kit_sync/connections.ex")

      assert source =~
               ~r/Connection\.approve_changeset[\s\S]+?error ->\s+log_sync_activity\("approved", connection, \[actor_uuid: admin_user_uuid\], %\{\s+"db_pending" => true\s+\}\)/,
             "approve_connection :error branch must call log_sync_activity with db_pending: true"
    end

    test "suspend_connection logs on :error with reason + db_pending" do
      source = File.read!("lib/phoenix_kit_sync/connections.ex")

      assert source =~
               ~r/Connection\.suspend_changeset[\s\S]+?error ->\s+log_sync_activity\("suspended", connection, \[actor_uuid: admin_user_uuid\], %\{\s+"reason" => reason,\s+"db_pending" => true\s+\}\)/,
             "suspend_connection :error branch must call log_sync_activity with db_pending: true"
    end

    test "revoke_connection logs on :error with reason + db_pending" do
      source = File.read!("lib/phoenix_kit_sync/connections.ex")

      assert source =~
               ~r/Connection\.revoke_changeset[\s\S]+?error ->\s+log_sync_activity\("revoked", connection, \[actor_uuid: admin_user_uuid\], %\{\s+"reason" => reason,\s+"db_pending" => true\s+\}\)/,
             "revoke_connection :error branch must call log_sync_activity with db_pending: true"
    end

    test "reactivate_connection logs on :error" do
      source = File.read!("lib/phoenix_kit_sync/connections.ex")

      assert source =~
               ~r/Connection\.reactivate_changeset[\s\S]+?error ->\s+log_sync_activity\("reactivated", connection, opts, %\{"db_pending" => true\}\)/,
             "reactivate_connection :error branch must call log_sync_activity with db_pending: true"
    end
  end

  # ---------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------

  defp create_active_sender_connection do
    {:ok, conn, _token} =
      Connections.create_connection(%{
        "name" => "Activity Test #{System.unique_integer([:positive])}",
        "direction" => "sender",
        "site_url" => "https://activity-#{System.unique_integer([:positive])}.example.com",
        "approval_mode" => "auto_approve"
      })

    {:ok, active} = Connections.approve_connection(conn, UUIDv7.generate())
    active
  end

  # Filter by action explicitly: `inserted_at` is second-precision and
  # the test inserts > 1 activity per second, so ORDER BY ties are
  # non-deterministic. The action filter pins the row we mean.
  defp latest_activity_for(uuid, action \\ "sync.connection.updated") do
    raw =
      TestRepo.query!(
        """
        SELECT action, actor_uuid, metadata
        FROM phoenix_kit_activities
        WHERE resource_uuid = $1 AND action = $2
        ORDER BY inserted_at DESC
        LIMIT 1
        """,
        [Ecto.UUID.dump!(uuid), action]
      )

    [[returned_action, actor_uuid_bytes, metadata]] = raw.rows

    %{
      action: returned_action,
      actor_uuid: actor_uuid_bytes && Ecto.UUID.load!(actor_uuid_bytes),
      metadata: metadata
    }
  end
end
