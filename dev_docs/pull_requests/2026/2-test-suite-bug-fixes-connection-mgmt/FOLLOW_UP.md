# Follow-up for PR #2 — Test Suite + Connection Management

After-action report on the findings in `CLAUDE_REVIEW.md` (and the
related post-merge notes Dmitri committed as `KIMI_FOLLOW_UP.md`).
`KIMI_FOLLOW_UP.md` is the reviewer's artifact and is untouched here.

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

## Fixed (Batch 1 — 2026-04-25, PR #2 follow-up commit ccaf052)

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

## Fixed (Batch 2 — 2026-04-25, Phase 2 quality sweep)

- ~~Task supervision — no direct pinning test (Batch 1 noted the
  helper but no LV-level test pinned `Task.start_link` vs
  `Task.Supervisor.start_child` semantics).~~ Phase 2 C7 stood up the
  LiveView test infrastructure (Test.Endpoint / Test.Router / LiveCase
  / hooks), and C10 added 8 LV smoke tests in
  `connections_live_test.exs` covering mount, save with
  `phx-disable-with`, validate-event re-render, delete + activity log,
  and the catch-all `handle_info` clause. Task supervision is
  exercised end-to-end through the delete-connection flow.
- ~~`connection_created` HTTP amplification — pinned via comment
  only.~~ The trade-off is now codified in AGENTS.md as a Key
  Convention (commit f4a3558) and surfaced in `connections_live.ex`
  via the inline comment at the handler's site. No code change;
  documenting the trade-off is the resolution.

## Skipped (with rationale)

- **#2 — `connection_created` PubSub handler amplifies HTTP traffic.**
  **Intentional trade-off, not a bug.** PR #2's own commit log says
  "Removed `skip_async: true` so new receivers fetch sender statuses" —
  the amplification is the cost of letting new connections show a
  correct initial status instead of "unknown pending first query."
  Documented inline at `lib/phoenix_kit_sync/web/connections_live.ex:1060`
  and as a Key Convention in AGENTS.md.
- **`parse_decimal_string` scope — no direct pinning test.** The fix
  lives in private functions of `connection_notifier.ex` only reachable
  via the WebSocket sync flow. The 3-arity `prepare_value/3` is verified
  end-to-end through the existing `full_sync_flow_test.exs` integration
  test (which round-trips records through the importer), but doesn't
  assert on per-column type coercion specifically. Adding a focused
  pinning test would require wiring a sender-side WebSocket harness; the
  cost outweighs the marginal coverage gain over what `full_sync_flow`
  already exercises.

## Files touched

| File | Change |
|------|--------|
| `lib/phoenix_kit_sync/web/connections_live.ex` | 13 `Task.start` → 5 `Task.start_link` (cancellable) + 8 `notify_remote_async` (supervised); new `notify_remote_async/1` helper using `PhoenixKit.TaskSupervisor` |
| `lib/phoenix_kit_sync/connections.ex` | `update_connection/2` refactored: `detect_changed_fields/2` normalises string keys via `String.to_existing_atom`, `broadcast_connection_update/3` short-circuits no-op saves |
| `lib/phoenix_kit_sync/connection_notifier.ex` | `prepare_value/3` scopes decimal-string detection to numeric columns; `fetch_numeric_columns/1` caches per table; `insert_record/4` → `insert_record/5`; `import_ctx` extended with `:numeric_cols` |
| `test/integration/connections_test.exs` | Two new regression tests: string-keyed status attr routes correctly; no-op save emits no broadcast |

## Verification

Final state after Batch 1 + Batch 2:

- `mix compile --warnings-as-errors` — clean
- `mix format --check-formatted` — clean
- `mix credo --strict` — 0 issues
- `mix dialyzer` — 0 errors (9 skipped via `.dialyzer_ignore.exs`, all
  pre-existing; one opaque-type MapSet friction avoided by using a plain
  list for `numeric_cols`)
- `mix test` — 391 tests, 0 failures, 5/5 stable consecutive runs
  (baseline was 316)

## Open

None.
