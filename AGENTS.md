# AGENTS.md

This file provides guidance to AI agents working with code in this repository.

## Project Overview

PhoenixKit Sync — an Elixir module for peer-to-peer data synchronization between PhoenixKit instances, built as a pluggable module for the PhoenixKit framework. Supports sync between dev↔prod, dev↔dev, or different websites entirely. Provides admin LiveViews for managing connections/transfers, REST API and WebSocket endpoints for cross-site communication, and Oban-based background import.

## Commands

```bash
mix test                    # Run all tests (integration excluded if no DB)
mix test test/file_test.exs # Run single test file
mix test test/file_test.exs:42  # Run specific test by line
mix format                  # Format code
mix credo --strict          # Lint / code quality (strict mode)
mix dialyzer                # Static type checking
mix precommit               # compile + format + credo --strict + dialyzer
mix deps.get                # Install dependencies
```

## Dependencies

This is a **library**, not a standalone app. It requires a sibling `../phoenix_kit` directory (path dependency). The full dependency chain:

- `phoenix_kit` (path: `"../phoenix_kit"`) — provides Module behaviour, Settings, RepoHelper, Dashboard tabs
- `phoenix`, `phoenix_live_view` — web framework
- `ecto_sql`, `postgrex` — database (via phoenix_kit)
- `websockex` — WebSocket client for connecting to remote senders
- `oban` — background job processing for imports
- `jason` — JSON encoding/decoding

## Architecture

This is a **PhoenixKit module** that implements the `PhoenixKit.Module` behaviour. It depends on the host PhoenixKit app for Repo, Endpoint, and Settings.

### Core Schemas

- **Connection** (`phoenix_kit_sync_connections`) — permanent token-based connection to a remote site, with auth token, table access config, IP whitelists, and time restrictions
- **Transfer** (`phoenix_kit_sync_transfers`) — transfer history record tracking direction, status, tables synced, and record counts

### Sync Modes

1. **Ephemeral code-based transfers** — one-time manual sync using a short-lived session code. SessionStore (ETS + GenServer with process monitoring) manages these sessions.
2. **Permanent token-based connections** — recurring sync using stored auth tokens with table-level access control.

### Data Pipeline

- **SchemaInspector** — database introspection (tables, columns, FKs, row counts)
- **DataExporter** — query and stream records for export with pagination
- **DataImporter** — import records with conflict strategies (skip, overwrite, merge, append)
- **ConnectionNotifier** — remote HTTP client for cross-site notifications, FK remapping, record transformation

### Communication Layer

- **Client / ChannelClient / WebSocketClient** — client-side sync protocol over WebSocket with heartbeat
- **ApiController** — REST API for cross-site sync operations (register, delete, verify connections; list tables; pull data)
- **SyncChannel / SyncSocket / SyncWebsock** — server-side WebSocket and Channel handlers
- **SocketPlug** — WebSocket upgrade plug

### Web Layer

- **Admin** (5 LiveViews): Index (dashboard), ConnectionsLive (manage connections), Receiver (receive data), Sender (send data), History (transfer log)
- **Public** (API + WebSocket): `ApiController` handles REST endpoints; `SyncSocket`/`SyncChannel` handle WebSocket sync protocol
- **Routes**: `route_module/0` provides public routes; admin routes auto-generated from `admin_tabs/0`
- **Paths**: Centralized path helpers in `Paths` module — always use these instead of hardcoding URLs

### Background Workers

- **ImportWorker** — Oban worker for large batch imports (max 3 retries)

### Settings Keys

`sync_enabled`, `sync_incoming_mode`, `sync_incoming_password`

### API Endpoints

All under the configured URL prefix (default: `/phoenix_kit`):

| Method | Path | Handler | Auth |
|--------|------|---------|------|
| POST | `/sync/api/register-connection` | Register incoming connection | Incoming mode + optional password |
| POST | `/sync/api/delete-connection` | Delete a connection | Module enabled |
| POST | `/sync/api/verify-connection` | Verify connection exists | Module enabled |
| POST | `/sync/api/update-status` | Update connection status | Module enabled |
| POST | `/sync/api/get-connection-status` | Query connection status | Module enabled |
| POST | `/sync/api/list-tables` | List available tables | Token + active connection |
| POST | `/sync/api/pull-data` | Pull table data | Token + active connection |
| POST | `/sync/api/table-schema` | Get table schema | Token + active connection |
| POST | `/sync/api/table-records` | Get table records | Token + active connection |
| GET | `/sync/api/status` | Check module status | None |
| WS | `/sync/websocket` | WebSocket sync protocol | Code or token in query params |

### File Layout

```
lib/phoenix_kit_sync.ex                    # Main module (PhoenixKit.Module behaviour)
lib/phoenix_kit_sync/
├── connection.ex                          # Connection Ecto schema + changesets
├── connections.ex                         # Connections context (CRUD, validation, activity logging)
├── transfer.ex                            # Transfer Ecto schema + changesets
├── transfers.ex                           # Transfers context (CRUD, lifecycle)
├── errors.ex                              # Single translation point for all error atoms → gettext strings
├── schema_inspector.ex                    # DB introspection (tables, columns, FKs); valid_identifier?/1 guards raw-SQL identifiers
├── data_exporter.ex                       # Record export with pagination + streaming
├── data_importer.ex                       # Record import with conflict strategies (parameterised SQL, batched find_existing)
├── connection_notifier.ex                 # HTTP client for remote site communication
├── connection_notifier/
│   └── prepare.ex                         # Value / record transformation helpers (ISO8601 parse, decimal-scope, field accessors)
├── session_store.ex                       # ETS-based ephemeral session management
├── column_info.ex                         # Column metadata struct
├── table_schema.ex                        # Table schema struct
├── client.ex                              # High-level sync client API
├── channel_client.ex                      # Channel-based sync client
├── websocket_client.ex                    # WebSockex-based sync client
├── paths.ex                               # Centralized URL path helpers
├── routes.ex                              # Route generation macro
├── migration.ex                           # Standalone migration (IF NOT EXISTS)
├── web/
│   ├── api_controller.ex                  # REST API for cross-site operations
│   ├── api_controller/
│   │   └── validators.ex                  # Param-shape validators (validate_register/delete/status/etc.)
│   ├── sync_websock.ex                    # WebSocket handler (WebSock behaviour)
│   ├── sync_channel.ex                    # Phoenix Channel handler
│   ├── sync_socket.ex                     # Phoenix Socket for channels
│   ├── socket_plug.ex                     # WebSocket upgrade plug
│   ├── index.ex                           # Admin dashboard LiveView
│   ├── connections_live.ex                # Admin connections management LiveView
│   ├── connections_live/
│   │   └── status.ex                      # Async status-fetch + verification helpers (linked tasks)
│   ├── sender.ex                          # Admin sender LiveView
│   ├── receiver.ex                        # Admin receiver LiveView
│   ├── receiver/
│   │   └── helpers.ex                     # Pure format/parse/count helpers for Receiver LV
│   └── history.ex                         # Admin transfer history LiveView
└── workers/
    └── import_worker.ex                   # Oban worker for batch imports
```

## Key Conventions

- **UUIDv7 primary keys** — all schemas use UUIDv7 primary keys
- **Oban workers** — all background tasks use Oban workers; never spawn bare Tasks for async import work
- **Centralized paths via `Paths` module** — never hardcode URLs or route paths in LiveViews or controllers; use `Paths` helpers
- **Admin routes from `admin_tabs/0`** — all admin navigation is auto-generated by PhoenixKit Dashboard from the tabs returned by `admin_tabs/0`; do not manually add admin routes elsewhere. See `phoenix_kit/guides/custom-admin-pages.md` for the authoritative reference (including why parent apps must never hand-register plugin LiveView routes)
- **Public routes from `route_module/0`** — the single public entry point is `PhoenixKitSync.Routes`; `route_module/0` returns this module so PhoenixKit registers public routes automatically
- **LiveViews use `Phoenix.LiveView` directly** — do not use `PhoenixKitWeb` macros (`use PhoenixKitWeb, :live_view`) in this standalone package; import helpers explicitly
- **SQL identifier safety** — always validate table/column names with `SchemaInspector.valid_identifier?/1` (public helper) and wrap with double quotes (`~s["#{name}"]`) before interpolating into any raw SQL. Values must always be passed as parameterised `$N` binds via `repo.query(sql, [binds])` — never concatenated into the SQL string. Reference impl: `DataImporter.find_existing/4` and `insert_record/3`
- **Errors → gettext via `PhoenixKitSync.Errors`** — every error atom the module emits has a clause in `Errors.message/1` that returns a `gettext/1`-translated string. Return `{:error, :atom}` tuples from context functions; translate at the UI/API boundary via `Errors.message(reason)`. Never return free-text error strings from context code. Unknown atoms fall through to `inspect/1`
- **Activity logging on mutations** — every state-changing operation in `Connections` calls `log_sync_activity/4`, which persists a `sync.connection.<verb>` entry via `PhoenixKit.Activity.log/1`. Guarded with `Code.ensure_loaded?/1` + `rescue` so a missing activities table never crashes the primary operation. Metadata captures `connection_name`/`direction`/`status`/`reason` only — NEVER `site_url` or auth-token fields (the audit feed is visible to other admins)
- **Task supervision** — async work in LiveViews is either `Task.start_link/1` (render-only fetches that should die with the LV) or `Task.Supervisor.start_child(PhoenixKit.TaskSupervisor, ..., restart: :temporary)` via the `notify_remote_async/1` helper (fire-and-forget notifications that must complete after a DB commit even if the admin closes the tab). Bare `Task.start/1` is forbidden
- **`Connection.ip_allowed?/2` quirk** — when `ip_whitelist` is empty (allow all), calling `ip_allowed?(conn, "127.0.0.1")` returns `false` because the 2-arity clause doesn't match the empty-list guard. The 1-arity `ip_allowed?(conn)` works correctly. Callers like `Connections.validate_connection/2` pass `nil` as IP to avoid this
- **Self-connection protection** — `Connections.create_connection/1` rejects sender connections to the site's own URL (with port/scheme/case normalization). Only applies to direction `"sender"` — receivers (API-created) are always allowed
- **PubSub broadcasts from context** — all state-changing operations in `Connections` broadcast via PubSub (`:connection_created`, `:connection_deleted`, `:connection_status_changed`, `:connection_updated`). Don't add duplicate broadcasts in controllers or LiveViews
- **Decimal values in sync** — `DataExporter` serializes `Decimal` to strings for JSON. `ConnectionNotifier.prepare_value/1` parses decimal-like strings (e.g., `"0.00"`) back to `Decimal` structs before INSERT. Without this, numeric columns fail with Postgrex type errors
- **Suggested tables in sync UI** — when tables are selected for sync, tables that reference them via FK are highlighted (not auto-selected) as "suggested". The admin decides whether to include them

## Testing

### Setup

The test database must be created manually:

```bash
createdb phoenix_kit_sync_test
mix test
```

Integration tests are automatically excluded when the database is unavailable. The test helper creates the `uuid_generate_v7()` function and runs `PhoenixKitSync.Migration` on first run.

The critical config wiring is in `config/test.exs`:

```elixir
config :phoenix_kit, repo: PhoenixKitSync.Test.Repo
```

Without this, all DB calls through `PhoenixKit.RepoHelper` crash with "No repository configured".

### Structure

```
test/
├── test_helper.exs                  # DB detection, migration, sandbox setup
├── support/
│   ├── test_repo.ex                 # PhoenixKitSync.Test.Repo
│   ├── data_case.ex                 # DataCase (sandbox + :integration tag)
│   └── changeset_helpers.ex         # errors_on/1 helper
├── phoenix_kit_sync/                # Unit tests (no DB, async: true)
│   ├── module_test.exs              # PhoenixKit.Module behaviour compliance
│   ├── connection_test.exs          # Connection changesets, access controls
│   ├── transfer_test.exs            # Transfer changesets, status logic
│   ├── session_store_test.exs       # ETS CRUD, process monitoring
│   ├── ephemeral_session_test.exs   # Session lifecycle via public API
│   ├── import_worker_test.exs       # Oban job changeset building
│   └── paths_test.exs              # URL path helpers
└── integration/                     # Integration tests (needs DB)
    ├── connections_test.exs         # Connections CRUD, validation, PubSub, self-connection
    ├── transfers_test.exs           # Transfer lifecycle + approval workflow
    ├── migration_test.exs           # Table structure verification
    ├── schema_inspector_test.exs    # Table listing, schema, checksums
    ├── data_exporter_test.exs       # Count, fetch, pagination, streaming
    ├── data_importer_test.exs       # All 4 conflict strategies
    ├── api_controller_test.exs      # Business logic + access control
    ├── sync_websock_test.exs        # WebSocket access control logic
    └── full_sync_flow_test.exs      # End-to-end export → import cycle
```

### Key patterns

- **Use string keys** for `Connections.create_connection/1` attrs — it injects a string key internally, causing `Ecto.CastError` with atom keys
- **Use `UUIDv7.generate()`** for any user UUID field (`approved_by_uuid`, etc.) — plain strings cause `Ecto.ChangeError`
- **Tag DB tests via `DataCase`** — the `@moduletag :integration` is set automatically
- **`enabled?/0` and `get_config/0` hit the DB** — test with `function_exported?/3` in unit tests, or tag as `:integration`
- **SessionStore uses a global ETS table** — use `setup_all` with `{:error, {:already_started, _}}` handling, not per-test `start_link`
- **Ecto schema types** — use `:integer` (not `:bigint`) and `:string` (not `:text`) in schemas; the migration-only types cause compilation errors
- **Run migrations via `Ecto.Migrator.up/4`** — calling `Migration.up()` directly fails outside a migrator process

### Running tests

```bash
mix test                             # All tests (excludes integration if no DB)
mix test test/phoenix_kit_sync/      # Unit tests only
mix test test/integration/           # Integration tests only
mix test --only integration          # Only integration-tagged tests
```

## PR Reviews

PR reviews are stored in `dev_docs/pull_requests/` and tracked in version control.

### Structure

```
dev_docs/pull_requests/<year>/<pr_number>-<slug>/{AGENT}_REVIEW.md
```

- **`<year>`** — year the PR was created (e.g., `2026`)
- **`<pr_number>`** — GitHub PR number (e.g., `1`)
- **`<slug>`** — short kebab-case summary from the PR title (e.g., `sync-module-extraction`)
- **`{AGENT}_REVIEW.md`** — review file named after the reviewing agent (e.g., `CLAUDE_REVIEW.md`, `GEMINI_REVIEW.md`, `KIMI_REVIEW.md`)

> **⚠️ Use YOUR OWN agent name:** If you are Kimi, use `KIMI_REVIEW.md`. If you are Claude, use `CLAUDE_REVIEW.md`. Never use another agent's name for your own review — each agent's reviews must be clearly attributable.

### Naming Rules for Multiple Reviews

When multiple agents review the same PR, each creates their own file:
```
dev_docs/pull_requests/2026/1-sync-module-extraction/
├── CLAUDE_REVIEW.md      # Claude's review
├── GEMINI_REVIEW.md      # Gemini's review
└── README.md
```

**Same agent, multiple reviews:** If the same agent reviews a PR multiple times (e.g., initial review + post-merge follow-up), append findings to the existing `{AGENT}_REVIEW.md` with a clear header, or use `FOLLOW_UP.md` for post-merge discoveries. Do NOT create files like `CLAUDE_REVIEW_2.md` — the `{AGENT}` prefix must match exactly and remain unique per agent.

### Review file format

```markdown
# Claude's Review of PR #<number> — <title>

**Verdict:** <Approve | Approve with follow-up items | Needs Work> — <reasoning>

## Critical Issues
### 1. <title>
**File:** <path>:<lines>
<Description, code snippet, fix>

## Security Concerns
## Architecture Issues
## Code Quality
### Issues
### Positives

## Recommended Priority
| Priority | Issue | Action |
```

Severity levels: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`

When issues are fixed in follow-up commits, append `— FIXED` to the issue title.

Additional files per PR directory:
- `README.md` — PR summary (what, why, files changed)
- `FOLLOW_UP.md` — post-merge issues, discovered bugs
- `CONTEXT.md` — alternatives considered, trade-offs

## Routing: Single Page vs Multi-Page

This module uses **both patterns**. Admin navigation is auto-generated from `admin_tabs/0` (three tabs: Overview / Connections / History), each with a `live_view:` binding. Public routes — the REST API and the WebSocket forward — go through a `route_module/0` (`PhoenixKitSync.Routes`) using `generate/1`.

> **`admin_routes/0` and `admin_locale_routes/0` can only contain `live` declarations** — Phoenix's `live_session` macro rejects controllers, `forward`, nested `scope`, and `pipe_through` at compile time. Non-LiveView routes (our `ApiController` endpoints and `SyncSocket` WebSocket forward) go in `generate/1` / `public_routes/1` instead. See `lib/phoenix_kit_sync/routes.ex` for the reference — it's the canonical example across the ecosystem of mixing a `forward` directive with controller routes in `generate/1`.

Sender / Receiver / History / Index LiveViews mount under `admin_tabs/0`; never hand-register them in a parent app's `router.ex` — they'd land outside the `:phoenix_kit_admin` `live_session` and crash on navigation.

## Tailwind CSS Scanning

`css_sources/0` returns `[:phoenix_kit_sync]` so the parent app's `:phoenix_kit_css_sources` compiler picks up sync's templates for Tailwind class scanning. Zero-config once the parent app has the compiler wired per core's `mix phoenix_kit.install` — adding or removing the sync module regenerates `_phoenix_kit_sources.css` automatically.

## Database & Migrations

The module owns two tables: `phoenix_kit_sync_connections` and `phoenix_kit_sync_transfers`. They're created either by:

- **Core `phoenix_kit` versioned migrations** (V37 / V44 / V56 / V58 / V74) when the parent app runs `PhoenixKit.Migrations.up()` — the canonical path.
- **`PhoenixKitSync.Migration`** standalone fallback with `CREATE TABLE IF NOT EXISTS`, used for fresh installs where the core migrations haven't run yet. Header at `lib/phoenix_kit_sync/migration.ex:1-10` documents which core V-numbers it mirrors — **if you modify table shape, keep this in sync with the canonical core migration**.

All schemas use `@primary_key {:uuid, UUIDv7, autogenerate: true}` + `uuid_generate_v7()` function in the DB.

## Versioning & Releases

This project follows [Semantic Versioning](https://semver.org/). Release cuts are done by the project maintainer — agents do not bump `@version` or edit `CHANGELOG.md` unless explicitly asked.

### Version locations

When bumping, update **two places**:

1. `mix.exs` — `@version` module attribute
2. `lib/phoenix_kit_sync.ex` — `def version, do: "x.y.z"`

(There is no dedicated version test in this module; the two must match manually.)

### Tagging & GitHub releases

Tags use **bare version numbers** (no `v` prefix):

```bash
git tag 0.1.1
git push origin 0.1.1
```

## Pre-commit Commands

Always run before `git commit`:

```bash
mix precommit               # compile + format + credo --strict + dialyzer
```

## Two Module Types (context)

PhoenixKit has two external module archetypes:

- **Template-only modules** (like `phoenix_kit_hello_world`) — showcase the conventions, have no schemas, no Errors module, minimal LiveView surface.
- **Feature modules** (like this one, `phoenix_kit_sync`) — own Ecto schemas, implement a full feature with CRUD, activity logging, admin LiveViews, and REST/WebSocket APIs. The `PhoenixKitSync.Errors` atom dispatcher + activity-logging helper in `Connections` are load-bearing for feature-module quality; template modules omit them.

When starting a new feature module, copy the file layout from this module or `phoenix_kit_catalogue`/`phoenix_kit_ai`. When starting a new template/showcase module, copy from `phoenix_kit_hello_world`.
