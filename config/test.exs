import Config

# Test database configuration
config :phoenix_kit_sync, ecto_repos: [PhoenixKitSync.Test.Repo]

config :phoenix_kit_sync, PhoenixKitSync.Test.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "phoenix_kit_sync_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Wire repo for PhoenixKit.RepoHelper (used by Connections, Transfers, etc.)
config :phoenix_kit, repo: PhoenixKitSync.Test.Repo

config :logger, level: :warning

# Test endpoint config — used by LiveView tests via
# `Phoenix.LiveViewTest.live/2`. Real production uses the host app's
# endpoint; this one is a minimal shim defined in
# `test/support/test_endpoint.ex`.
config :phoenix_kit_sync, PhoenixKitSync.Test.Endpoint,
  # Bandit is a transitive dep via phoenix; Cowboy isn't, so explicitly
  # set the adapter here. http: port: 0 binds a random free port; the
  # test_helper reads it back via Application env so tests can build
  # localhost URLs that ConnectionNotifier / WebSocketClient reach.
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 0],
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  render_errors: [formats: [html: PhoenixKitSync.Test.Layouts]],
  live_view: [signing_salt: "sync-test-live-view-salt"],
  pubsub_server: PhoenixKitSync.Test.PubSub,
  server: true
