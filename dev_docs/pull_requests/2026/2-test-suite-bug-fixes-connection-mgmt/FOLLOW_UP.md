# Follow-up for PR #2 — Test Suite + Connection Management

Post-merge triage of the findings in `CLAUDE_REVIEW.md` (and the related
post-merge notes Dmitri committed as `KIMI_FOLLOW_UP.md`) against the code
on `main` as of 2026-04-25. `KIMI_FOLLOW_UP.md` is the reviewer's
artifact and is untouched here.

## Fixed (pre-existing)

- ~~#5 — Error struct shape assumption in `notify_delete`.~~ Already handles
  both `%{reason: reason}` and `{:error, reason}` catch-all
  (`lib/phoenix_kit_sync/connection_notifier.ex:248-254`).
- ~~#6 — Migration DDL drift without a reference to canonical migrations.~~
  The standalone migration now documents the upstream versions it mirrors
  (`lib/phoenix_kit_sync/migration.ex:1-10` references V37/V44/V56/V58/V74).
- ~~#7 — `connections_test` forced to `async: false`.~~ Accepted as-is: the
  shared PubSub topic is necessary for the broadcast tests, and switching
  to per-test unique topics was a *backlog* item in the original review,
  not a correctness concern.

## Fixed (Batch 1 — 2026-04-25)

- ~~#1 — Unsupervised `Task.start/1` calls.~~ All 13 occurrences in
  `lib/phoenix_kit_sync/web/connections_live.ex` are now categorised and
  supervised:
  - **Linked** (`Task.start_link/1`) for cancellable render-only fetches
    that only feed the LV's own display: sender-status fetch (line 192),
    per-connection verification (line 227), table-picker fetch (720),
    table-schema fetch (762), preview-records fetch (802). These die
    cleanly when the LV dies — no orphan HTTP calls.
  - **Supervised** (`Task.Supervisor.start_child(PhoenixKit.TaskSupervisor,
    ..., restart: :temporary)` via a new `notify_remote_async/1` helper)
    for fire-and-forget side effects that must complete after the DB
    commit: approve/suspend/reactivate/revoke status notifications, delete
    notification, start_detail_sync, pull_table_data_with_remap, and
    post-creation remote notification (lines 309, 332, 354, 377, 412,
    848, 941, 2978).
  The helper lives at the bottom of `connections_live.ex:2994-2998` — it'll
  migrate cleanly when the LiveView gets split in the Wave 2 god-module
  decomposition.
- ~~#3 — `parse_decimal_string` applied too broadly.~~ Added a 3-arity
  `prepare_value(value, column, numeric_cols)` in `connection_notifier.ex`
  that scopes `parse_decimal_string/1` to columns whose Postgres type is
  one of `numeric`/`decimal`/`double precision`/`real`
  (`lib/phoenix_kit_sync/connection_notifier.ex:1549-1595`). The column
  metadata is fetched once per table via `fetch_numeric_columns/1` and
  threaded through `import_ctx.numeric_cols` into `insert_record/5`. The
  1-arity `prepare_value/1` is retained for the PK/unique-column lookup
  paths (`check_pk_exists`, `find_match_by_unique`) where the broad match
  is still safe because the values are known keys, not free-text columns.
  Fetches degrade to `[]` if the schema is unreachable, so the safe "don't
  coerce" branch always wins on error.
- ~~#4 — `changed_fields` atom-key comparison.~~ Replaced the old
  `Enum.reject(fn {k, v} -> Map.get(connection, k) == v end)` with
  `detect_changed_fields/2`, which resolves string keys via
  `String.to_existing_atom/1` with an `ArgumentError` rescue and drops
  unknown keys rather than treating them as "changed"
  (`lib/phoenix_kit_sync/connections.ex:322-350`). Also fixed a latent
  bug discovered by the regression test: the old code broadcast
  `:connection_updated` unconditionally on every save; when
  `detect_changed_fields` returns `[]` (no-op save) the new
  `broadcast_connection_update/3` helper short-circuits with `:ok` — no
  log, no PubSub churn. Two new regression tests pin the fix:
  string-keyed `"status"` routes to `:connection_status_changed`, and a
  literal no-op save emits nothing
  (`test/integration/connections_test.exs:482-520`).

## Skipped (with rationale)

- **#2 — `connection_created` PubSub handler amplifies HTTP traffic.**
  **Intentional trade-off, not a bug.** PR #2's own commit log says
  "Removed `skip_async: true` so new receivers fetch sender statuses" —
  the amplification is the cost of letting new connections show a
  correct initial status instead of "unknown pending first query."
  `lib/phoenix_kit_sync/web/connections_live.ex:1060` has a comment
  explaining why. Left open in `## Open` below with a pointer to
  debouncing as a future option that could resolve both without
  sacrificing correctness.

## Files touched

| File | Change |
|------|--------|
| `lib/phoenix_kit_sync/web/connections_live.ex` | 13 `Task.start` → 5 `Task.start_link` (cancellable) + 8 `notify_remote_async` (supervised); new `notify_remote_async/1` helper using `PhoenixKit.TaskSupervisor` |
| `lib/phoenix_kit_sync/connections.ex` | `update_connection/2` refactored: `detect_changed_fields/2` normalises string keys via `String.to_existing_atom`, `broadcast_connection_update/3` short-circuits no-op saves |
| `lib/phoenix_kit_sync/connection_notifier.ex` | `prepare_value/3` scopes decimal-string detection to numeric columns; `fetch_numeric_columns/1` caches per table; `insert_record/4` → `insert_record/5`; `import_ctx` extended with `:numeric_cols` |
| `test/integration/connections_test.exs` | Two new regression tests: string-keyed status attr routes correctly; no-op save emits no broadcast |

## Verification

- `mix compile --warnings-as-errors` — clean
- `mix format --check-formatted` — clean
- `mix credo --strict` — 0 issues
- `mix dialyzer` — 0 errors (9 skipped via `.dialyzer_ignore.exs`, all
  pre-existing; one opaque-type MapSet friction avoided by using a plain
  list for `numeric_cols`)
- `mix test` — 320 tests, 0 failures (baseline 316 after PR #1 follow-up
  was 318; +2 connection regression tests)

## Open

- **#2 — HTTP amplification on `connection_created`.** Documented above as
  intentional. If it becomes a real load problem on an admin with many
  sessions open simultaneously, the resolution is a per-session debounce
  (e.g. `Process.send_after(self(), {:debounced_reload, ref}, 300)` with
  a ref check) rather than reinstating `skip_async: true`, which would
  regress the "new receivers show correct sender status" property.
- **`parse_decimal_string` scope — no direct pinning test.** The fix
  lives in private functions of `connection_notifier.ex` only reachable
  via the WebSocket sync flow, which `full_sync_flow_test.exs` exercises
  at coarse grain but doesn't assert on per-column type coercion. A
  focused pinning test is deferred to the Phase 2 C10 LiveView smoke
  tests, where the full sender→receiver sync path will get proper test
  infra.
- **Task supervision — no direct pinning test.** LiveView test infra
  doesn't exist in this package yet (C7 deliverable). Supervised vs
  linked is verified only by compile + manual smoke for now.
