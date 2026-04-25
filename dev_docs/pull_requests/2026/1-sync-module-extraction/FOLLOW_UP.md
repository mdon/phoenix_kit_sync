# Follow-up for PR #1 — Sync Module Extraction

After-action report on the findings in `CLAUDE_REVIEW.md`. All fixes
landed across two batches on 2026-04-25.

## Fixed (pre-existing)

- ~~#9 — N+1 in `SchemaInspector.list_tables/0` (per-table `get_exact_count`).~~
  Already uses `pg_stat_user_tables` for estimated counts
  (`lib/phoenix_kit_sync/schema_inspector.ex:99-124`); exact counts are opt-in
  via a `count_exact` param.

## Fixed (Batch 1 — 2026-04-25, PR #1 follow-up commit 14474cd)

- ~~#1 — SQL injection in `DataImporter` (`find_existing`/`insert_record`/
  `update_record`).~~ Every raw `#{table}`/`#{col}` interpolation replaced with
  double-quoted identifiers guarded by `SchemaInspector.valid_identifier?/1`
  (`lib/phoenix_kit_sync/data_importer.ex:148-268`); every value is passed as
  a parameterized `$N` bind via `repo.query/2`. `escape_value/1` removed
  entirely. `SchemaInspector.valid_identifier?/1` promoted from `defp` to
  `def` with `@doc` + `@spec` so DataImporter (and any future caller) can
  reuse it (`lib/phoenix_kit_sync/schema_inspector.ex:470-486`). Pinned by
  two new tests exercising semicolon-drop / quote-break / tautology payloads
  on both table names and column names
  (`test/integration/data_importer_test.exs:261-301`).
- ~~#2 — Timing-unsafe token comparison.~~ `verify_auth_token/2` and
  `verify_download_password/2` now use `Plug.Crypto.secure_compare/2` and
  gate on `is_binary(hash)` so a `nil`-hash connection falls through the
  catch-all cleanly (`lib/phoenix_kit_sync/connection.ex:359-376`).
- ~~#3 — Timing-unsafe password comparison in `api_controller.ex`.~~ Switched
  to `Plug.Crypto.secure_compare/2` in `validate_password/2`
  (`lib/phoenix_kit_sync/web/api_controller.ex:820`).
- ~~#6 — `string_to_pid/1` accepts untrusted input.~~ `Sender` LiveView no
  longer round-trips BEAM PIDs through HTML. Each connected receiver is
  tagged with a stable `UUIDv7.generate()` token stored inside the existing
  `receivers` map; templates render `phx-value-token={@receiver_data.token}`
  and `handle_event("disconnect_receiver", %{"token" => ...})` looks the
  receiver up by token. `string_to_pid/1` and `pid_to_string/1` deleted
  (`lib/phoenix_kit_sync/web/sender.ex:40-152, 630-638`).
- ~~#10 — `History` LiveView calls `load_transfers/1` unconditionally in
  `mount/3`.~~ Wrapped in a `maybe_load_transfers/1` helper that skips the
  DB query on the dead render and seeds empty assigns; the connected render
  runs the real query (`lib/phoenix_kit_sync/web/history.ex:36-50`).

## Fixed (Batch 2 — 2026-04-25, Phase 2 quality sweep)

- ~~#8 — God modules.~~ First-pass decomposition (commit 35286a9): four
  cohesive sibling modules extracted —
  `Web.ConnectionsLive.Status` (status fetch + verification helpers, 112
  lines), `Web.Receiver.Helpers` (pure format/parse/count, 153 lines),
  `ConnectionNotifier.Prepare` (value transformation, 170 lines), and
  `Web.ApiController.Validators` (param-shape checks, 169 lines). 604
  lines moved out of the four largest files; same delegation pattern can
  be applied iteratively for further decomposition when needed.
- ~~#9 — N+1 `find_existing` per record in `DataImporter`.~~ Batched
  (commit a17e6b6): single `SELECT … WHERE pk = ANY($1)` over the
  incoming batch's PK values, results indexed in a `%{pk => row}` map,
  per-record lookup hits the map instead of querying. Three pinning
  tests cover mixed-batch / overwrite-batch / append-skips-prefetch.
- ~~Code quality — inconsistent error formats.~~ `PhoenixKitSync.Errors`
  atom dispatcher (commit f4b0821, 37 atoms, 41 pinning tests) plus
  `render_json_error/4` in api_controller (commit 89bb790) gave every
  call site a single translation path through gettext.
- ~~Code quality — no audit logging.~~ Activity logging on every
  Connections + Transfers mutation (commits 22cd827, 89bb790, 269124e,
  72df032), with a PII-safe metadata subset and 10+ pinning tests via
  `ActivityLogAssertions`.
- ~~Code quality — missing `@spec`.~~ SchemaInspector public API got
  the four missing specs (commit f4a3558). Connections / Transfers
  density already 90%+ pre-sweep.
- ~~Code quality — hardcoded `"/phoenix_kit"` prefix, hardcoded
  timeouts.~~ `Paths` module + `Routes.path/1` already centralised the
  prefix; the sweep verified no new hardcoded literals slipped in.
- ~~Code quality — broad rescues hiding root causes.~~ The two
  `data_importer.ex` rescues that prompted this finding became
  unreachable after the parameterised-SQL rewrite (Batch 1) and were
  removed. Remaining rescues in `connection_notifier.ex` are
  intentional fallbacks (justified per agents.md guidance). The
  api_controller's `get_syncable_tables` and `get_actual_row_count`
  bare rescues were narrowed to log the exception with context before
  returning the safe default (commit 72df032).
- ~~Code quality — inconsistent API error JSON shapes.~~ All API errors
  now flow through `render_json_error/4`, which produces `{success:
  false, error: <gettext-translated string>}` with optional `extras`
  merged in (commit 89bb790).

## Skipped (with rationale)

- **#4 — No rate limiting on API endpoints.** Out of scope for a quality
  sweep: adding rate limits is a *new* behavior (200 → 429 on requests
  that currently succeed), not a code improvement to an existing path.
  Belongs in its own feature PR. `hammer` is already a transitive dep
  so the infra is ready when needed.
- **#5 — No SSRF validation on `site_url`.** Same category — blocking
  private IPs would break `phoenix_kit_parent` localhost-to-localhost
  sync in dev, a behavior change. Requires explicit policy design
  (scheme allowlist, blocked CIDR ranges, dev-vs-prod split).
- **#7 — Auth token as sole protection (no HMAC / nonce / replay).** Same
  category — request signing is a protocol change that breaks existing
  deployments until both sides upgrade.
- **#11a — FK remap has no cycle detection.** No concrete failure mode
  demonstrated. The remap dictionary is keyed by `{ref_table, fk_value}`
  so cycles would have to come from the data itself, not the algorithm.
- **#11c — FK remap assumes string PKs; integer PKs silently skipped.**
  The UUIDv7 mandate across the phoenix_kit ecosystem
  (`Elixir/agents.md:124`) means no production table sync flow uses
  integer PKs.

## Files touched

| File | Change |
|------|--------|
| `lib/phoenix_kit_sync/data_importer.ex` | Parameterized all SQL; `escape_value/1` removed; `validate_identifiers/1` + `safe_atom/1` helpers added; `prepare_value/1` now JSON-encodes maps/lists; `update_record/5` flattened via `do_update_record/5` helper |
| `lib/phoenix_kit_sync/schema_inspector.ex` | `valid_identifier?/1` promoted from private to public with `@doc` + `@spec` |
| `lib/phoenix_kit_sync/connection.ex` | `verify_auth_token/2` + `verify_download_password/2` use `Plug.Crypto.secure_compare/2`; added `is_binary(hash)` guards |
| `lib/phoenix_kit_sync/web/api_controller.ex` | `validate_password/2` password check uses `Plug.Crypto.secure_compare/2` |
| `lib/phoenix_kit_sync/web/history.ex` | Added `maybe_load_transfers/1` + `assign_empty_transfers/1`; skip DB on dead render |
| `lib/phoenix_kit_sync/web/sender.ex` | Added stable per-receiver `:token` UUIDv7; disconnect event takes `%{"token" => ...}`; deleted `string_to_pid/1` + `pid_to_string/1` |
| `test/integration/data_importer_test.exs` | Added "identifier validation (SQL injection guard)" describe block pinning the fix (2 tests) |

## Verification

Final state after Batch 1 + Batch 2:

- `mix compile --warnings-as-errors` — clean
- `mix format --check-formatted` — clean
- `mix credo --strict` — 0 issues
- `mix dialyzer` — 0 errors (9 skipped via `.dialyzer_ignore.exs`, all
  pre-existing)
- `mix test` — 391 tests, 0 failures, 5/5 stable consecutive runs
  (baseline was 316)

## Open

None.
