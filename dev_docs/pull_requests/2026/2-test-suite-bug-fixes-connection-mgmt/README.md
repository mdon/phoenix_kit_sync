# PR #2: Add Test Suite, Fix Sync Bugs, Improve Connection Management and UI

**Author**: @mdon (Max Don)
**Co-authored with**: Claude Opus 4.6
**Status**: Merged
**Commits**: `c825e15..6f17355` (17 commits)
**Date**: 2026-03-21 to 2026-03-22

## Goal

Build a comprehensive test suite for PhoenixKitSync (from 0 to 316 tests), fix production bugs discovered during testing, and improve connection lifecycle management for real-world deployment scenarios (shared-DB localhost, cross-site deletion, auto-activation).

## What Was Changed

### Production Code Modified (12 files, +508/-61)

| File | Lines | Change |
|------|-------|--------|
| `lib/phoenix_kit_sync/connections.ex` | +217/-19 | Self-connection protection, PubSub broadcasts from context, extracted helpers for credo compliance |
| `lib/phoenix_kit_sync/web/connections_live.ex` | +177/-24 | PubSub handlers, suggested table highlighting, approve button for pending senders, suspend-on-severed |
| `lib/phoenix_kit_sync/web/api_controller.ex` | +29/-35 | Removed duplicate PubSub broadcasts (now handled by context), logging cleanup |
| `lib/phoenix_kit_sync/connection_notifier.ex` | +19/-2 | `get_our_site_url/0` made public, `prepare_value/1` decimal string parsing |
| `lib/phoenix_kit_sync/transfers.ex` | +58/-0 | Logger calls on all state-changing operations |
| `lib/phoenix_kit_sync/data_exporter.ex` | +5/-2 | Fix `serialize_value` clause ordering (struct before map guard) |
| `lib/phoenix_kit_sync/schema_inspector.ex` | +1/-1 | Fix nil `primary_key` causing `BadBooleanError` |
| `lib/phoenix_kit_sync/migration.ex` | +320/-0 | New standalone migration module with IF NOT EXISTS |
| `lib/phoenix_kit_sync/web/sync_channel.ex` | +1/-1 | Fix version atom `:phoenix_kit` -> `:phoenix_kit_sync` |
| `lib/phoenix_kit_sync/web/sync_websock.ex` | +1/-1 | Same version atom fix |
| `mix.exs` | +7/-1 | `elixirc_paths` for test support, `test.setup`/`test.reset` aliases |
| `config/config.exs` | +5/-0 | Test-related config |

### Test Infrastructure Added (4 files)

| File | Description |
|------|-------------|
| `config/test.exs` | Test repo config, wires `PhoenixKitSync.Test.Repo` to `PhoenixKit.RepoHelper` |
| `test/test_helper.exs` | DB detection, `uuid_generate_v7()` setup, migration runner, sandbox |
| `test/support/data_case.ex` | DataCase with sandbox checkout + `:integration` tag |
| `test/support/test_repo.ex` | `PhoenixKitSync.Test.Repo` module |
| `test/support/changeset_helpers.ex` | `errors_on/1` helper |

### Unit Tests Added (7 files, ~1,770 lines)

| File | Tests | Coverage |
|------|-------|----------|
| `connection_test.exs` | 678 lines | All changesets, access controls, token verification, hours logic |
| `transfer_test.exs` | 430 lines | All changesets, status transitions, approval, computed fields |
| `session_store_test.exs` | 219 lines | ETS CRUD, process monitoring, concurrency |
| `ephemeral_session_test.exs` | 193 lines | Session lifecycle via PhoenixKitSync public API |
| `module_test.exs` | 135 lines | PhoenixKit.Module behaviour compliance |
| `import_worker_test.exs` | 83 lines | Oban job changeset building |
| `paths_test.exs` | 32 lines | URL path helpers |

### Integration Tests Added (9 files, ~1,938 lines)

| File | Tests | Coverage |
|------|-------|----------|
| `connections_test.exs` | 481 lines | CRUD, status transitions, token validation, limits, self-connection, PubSub |
| `full_sync_flow_test.exs` | 324 lines | End-to-end export -> import with transfer tracking |
| `data_importer_test.exs` | 260 lines | All 4 conflict strategies (skip/overwrite/merge/append) |
| `transfers_test.exs` | 187 lines | Full lifecycle, approval workflow, queries, stats |
| `sync_websock_test.exs` | 181 lines | WebSocket access control and connection state checks |
| `schema_inspector_test.exs` | 165 lines | Table listing, schema introspection, checksums, create_table |
| `api_controller_test.exs` | 150 lines | Business logic flow, token hashing, table access control |
| `data_exporter_test.exs` | 104 lines | Count, fetch, pagination, streaming |
| `migration_test.exs` | 86 lines | Table structure and constraint verification |

### Documentation Updated (3 files)

| File | Change |
|------|--------|
| `AGENTS.md` | Dependencies, API endpoints, file layout, testing guide, key conventions |
| `README.md` | Architecture, API docs, connection settings, workflow guides |
| `docs/table_structure.md` | Types/defaults to match actual DB schema |

## Implementation Details

### Bugs Fixed

1. **`DataExporter.serialize_value` clause ordering**: `is_map` guard matched structs (`DateTime`, `NaiveDateTime`) before struct-specific clauses, crashing on any table with timestamps. Fixed by moving `is_map` clause after all struct matchers.

2. **`SchemaInspector.column_to_sql` nil primary_key**: `nil and ...` expression caused `BadBooleanError`. Fixed with `!!` coercion.

3. **Decimal serialization roundtrip**: `DataExporter` serializes `Decimal` to strings for JSON transport, but `ConnectionNotifier` wasn't converting them back before INSERT. Added `parse_decimal_string/1` using `~r/^-?\d+\.\d+$/` to detect and reconvert.

### Connection Lifecycle Improvements

- **Self-connection protection**: `create_connection/1` rejects sender connections to own `site_url` with URL normalization (scheme, host, port, case). Only applies to `"sender"` direction.
- **PubSub centralization**: All broadcasts moved from `ApiController` to `Connections` context. Events: `:connection_created`, `:connection_deleted`, `:connection_status_changed`, `:connection_updated`.
- **Suspend instead of delete on severed**: `receiver_connection_severed` now suspends rather than auto-deleting, preventing cascade on shared-DB localhost setups.
- **Approve button for pending senders**: UI affordance for manual approval on shared-DB setups where auto-activation doesn't trigger.
- **Bidirectional delete notifications**: Both sender and receiver deletions now notify the remote site.
- **Fix `connection_created` handler**: Removed `skip_async: true` so new receivers fetch sender statuses.
- **Auto-activation audit trail**: Records `approved_at` and metadata on auto-activated connections.

### Sync UI

- **Suggested tables**: When tables are selected, FK-dependent tables highlighted with `bg-warning/10` and tooltip. Computed from reverse FK dependencies.
- **Legend**: Explains selected (blue) vs suggested (yellow) highlighting.

## Commit History

The 17 commits show iterative development with one revert cycle:

1. `c825e15` — Schema/migration type fixes, version bug, docs
2. `64c5889` — Test suite (305 tests) + 2 bug fixes
3. `dd35363` — Self-connection protection + audit trail + logging
4. `93593b5` — PubSub broadcasts to context
5. `bee8150` — Suspend on severed (replacing auto-delete)
6. `6797cc1` — Approve button for pending senders
7. `7948483` — Bidirectional delete notifications
8. `2bcf1d0` — 5s verify delay (to fix a race)
9. `8e31a73` — Self-connection check: sender-only
10. `f56a841` — Revert verify delay (unnecessary)
11. `a72291a` — Fix connection_created handler
12. `e98cda9` — Tests for self-connection + PubSub
13. `f5ffbc4` — Credo complexity + dialyzer fix
14. `c2931a0` — Decimal serialization fix
15. `94a8d2d` — Suggested table highlighting
16. `bdbefdb` — Clean up highlighting + legend
17. `6f17355` — AGENTS.md update + format test files

## Related

- Previous: [PR #1 — Sync Module Extraction](/dev_docs/pull_requests/2026/1-sync-module-extraction/)
