# Test helper for PhoenixKitSync test suite
#
# Unit tests (schemas, changesets, pure functions) run without a database.
# Integration tests require a running PostgreSQL — they are automatically
# excluded when the DB is unavailable.

alias PhoenixKitSync.Test.Repo, as: TestRepo

# Check if the test database exists before trying to connect
db_config = Application.get_env(:phoenix_kit_sync, TestRepo, [])
db_name = db_config[:database] || "phoenix_kit_sync_test"

db_check =
  case System.cmd("psql", ["-lqt"], stderr_to_stdout: true) do
    {output, 0} ->
      exists =
        output
        |> String.split("\n")
        |> Enum.any?(fn line ->
          line |> String.split("|") |> List.first("") |> String.trim() == db_name
        end)

      if exists, do: :exists, else: :not_found

    _ ->
      :try_connect
  end

repo_available =
  if db_check == :not_found do
    IO.puts("""
    \n⚠  Test database "#{db_name}" not found — integration tests will be excluded.
       Run: createdb #{db_name}
    """)

    false
  else
    try do
      {:ok, _} = TestRepo.start_link()

      # Enable uuid-ossp extension
      TestRepo.query!("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

      # Create uuid_generate_v7() function (normally created by PhoenixKit V40 migration)
      TestRepo.query!("""
      CREATE OR REPLACE FUNCTION uuid_generate_v7()
      RETURNS uuid AS $$
      DECLARE
        unix_ts_ms bytea;
        uuid_bytes bytea;
      BEGIN
        unix_ts_ms := substring(int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3);
        uuid_bytes := unix_ts_ms || gen_random_bytes(10);
        uuid_bytes := set_byte(uuid_bytes, 6, (get_byte(uuid_bytes, 6) & 15) | 112);
        uuid_bytes := set_byte(uuid_bytes, 8, (get_byte(uuid_bytes, 8) & 63) | 128);
        RETURN encode(uuid_bytes, 'hex')::uuid;
      END;
      $$ LANGUAGE plpgsql VOLATILE;
      """)

      # Run sync migration to create tables via Ecto.Migrator
      Ecto.Migrator.up(TestRepo, 0, PhoenixKitSync.Migration, log: false)

      # Create a minimal phoenix_kit_activities table so
      # PhoenixKit.Activity.log/1 calls from Connections mutations succeed
      # without polluting test output with "relation does not exist"
      # warnings. Shape matches the real schema that core phoenix_kit
      # migrations build (uuid PK via uuid_generate_v7, JSONB metadata,
      # timestamps). Without this, every mutation in the suite logged a
      # warning even though the operation itself succeeded.
      TestRepo.query!("""
      CREATE TABLE IF NOT EXISTS phoenix_kit_activities (
        uuid uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
        action varchar(255) NOT NULL,
        module varchar(100),
        mode varchar(50),
        actor_uuid uuid,
        resource_type varchar(100),
        resource_uuid uuid,
        target_uuid uuid,
        metadata jsonb DEFAULT '{}'::jsonb,
        inserted_at timestamp without time zone DEFAULT NOW()
      )
      """)

      # Create phoenix_kit_settings with the REAL schema columns. LiveView
      # mounts read `PhoenixKit.Settings.get_project_title/0` which queries
      # this table; without it, every LV test crashes before render.
      # Column shape is load-bearing: a mismatch ("column module does not
      # exist") aborts the sandbox transaction — every subsequent query
      # in the same test fails with "current transaction is aborted".
      # See agents.md:664-673.
      TestRepo.query!("""
      CREATE TABLE IF NOT EXISTS phoenix_kit_settings (
        uuid uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
        key varchar(255) NOT NULL UNIQUE,
        value text,
        value_json jsonb,
        module varchar(100),
        date_added timestamp without time zone DEFAULT NOW(),
        date_updated timestamp without time zone DEFAULT NOW()
      )
      """)

      Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
      true
    rescue
      e ->
        IO.puts("""
        \n⚠  Could not connect to test database — integration tests will be excluded.
           Run: createdb #{db_name}
           Error: #{Exception.message(e)}
        """)

        false
    catch
      :exit, reason ->
        IO.puts("""
        \n⚠  Could not connect to test database — integration tests will be excluded.
           Run: createdb #{db_name}
           Error: #{inspect(reason)}
        """)

        false
    end
  end

Application.put_env(:phoenix_kit_sync, :test_repo_available, repo_available)

# Start minimal services needed for tests
{:ok, _pid} = PhoenixKit.PubSub.Manager.start_link([])
{:ok, _pid} = PhoenixKit.ModuleRegistry.start_link([])

# Start PhoenixKit.TaskSupervisor so PhoenixKitSync.AsyncTasks can route
# fire-and-forget tasks through the named supervisor as it does in
# production. Without this, the helper's `:exit` fallback fires and tests
# can't distinguish supervised from bare `Task.start`.
case Task.Supervisor.start_link(name: PhoenixKit.TaskSupervisor) do
  {:ok, _pid} -> :ok
  {:error, {:already_started, _pid}} -> :ok
end

# Start the test endpoint so Phoenix.LiveViewTest.live/2 can drive
# LiveViews through `/en/admin/sync/*` URLs. Only when the DB is
# available (otherwise integration tests are excluded anyway).
if repo_available do
  {:ok, _pid} = PhoenixKitSync.Test.Endpoint.start_link()

  # Pin URL prefix to "" via :persistent_term so PhoenixKit.Utils.Routes
  # doesn't try to query the settings table for the live URL prefix
  # during test mounts (which would be a cross-process sandbox query).
  :persistent_term.put({PhoenixKit.Config, :url_prefix}, "")
end

# Exclude integration tests when DB is not available
exclude = if repo_available, do: [], else: [:integration]

ExUnit.start(exclude: exclude)
