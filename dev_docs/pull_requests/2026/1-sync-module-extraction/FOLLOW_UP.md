# Follow-up for PR #1 — Sync Module Extraction

Post-merge triage of the findings in `CLAUDE_REVIEW.md` against the code on
`main` as of 2026-04-25.

## Fixed (pre-existing)

- ~~#9 — N+1 in `SchemaInspector.list_tables/0` (per-table `get_exact_count`).~~
  Already uses `pg_stat_user_tables` for estimated counts
  (`lib/phoenix_kit_sync/schema_inspector.ex:99-124`); exact counts are opt-in
  via a `count_exact` param.

## Fixed (Batch 1 — 2026-04-25)

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

## Skipped (with rationale)

- **#4 — No rate limiting on API endpoints.** Out of scope for this quality
  sweep: adding rate limits is a *new* behavior (200 → 429 on requests that
  currently succeed), not a code improvement to an existing path. Belongs
  in its own feature PR if/when rate limiting is a policy decision.
  `hammer` is already a transitive dep, so the infra is ready whenever that
  PR happens.
- **#5 — No SSRF validation on `site_url`.** Same category — adding private-IP
  blocks would break existing workflows (e.g. `phoenix_kit_parent`
  localhost-to-localhost sync in dev), which is a behavior change, not a
  code quality fix. Requires explicit policy design (scheme allowlist,
  blocked CIDR ranges, dev-vs-prod split) before any code lands.
- **#7 — Auth token as sole protection (no HMAC / nonce / replay
  protection).** Same category — introducing request signing is a protocol
  change that breaks existing deployments until both sides upgrade. Feature
  work, not quality sweep.
- **#8 — God modules (`connections_live.ex` 2982 lines / `receiver.ex` 2047 /
  `connection_notifier.ex` 1648 / `api_controller.ex` 1292).** Each file
  gets its own dedicated PR in a follow-up wave of the sweep — mixing the
  decomposition into this commit would bury the security fixes under
  3000-line diffs. Same-behavior refactor, in scope for quality work.
- **#9 — N+1 `find_existing` per record in `DataImporter`.** Batching
  requires threading a per-import-batch lookup cache through the conflict
  path; natural fit with the upcoming "Importer batching" PR that also
  caches SchemaInspector calls per sync session (#11b). Same-behavior
  refactor, in scope.
- **#11a — FK remap has no cycle detection.** Code review found no graph
  traversal in `connection_notifier.ex:1290-1480`, but no concrete failure
  mode has been demonstrated. Left under `## Open` pending a reproducer.
- **#11b — Schema inspection runs per import instead of per session.** Real
  perf concern for many-table syncs. Folded into the upcoming "Importer
  batching" PR.
- **#11c — FK remap assumes string PKs; integer PKs silently skipped
  (`connection_notifier.ex:1463` guards on `is_binary/1`).** Given the
  UUIDv7 mandate across phoenix_kit schemas
  (`Elixir/agents.md:124`), no production table in the ecosystem has
  integer PKs that flow through sync. Document the assumption during the
  `connection_notifier.ex` split PR rather than paper over it here.
- **Code quality items (inconsistent error formats, broad rescues, hardcoded
  `"/phoenix_kit"` prefix + `@base "/admin/sync"` + timeouts, missing `@spec`,
  no telemetry, no audit logging, inconsistent API error JSON shapes).**
  These are all Phase 2 quality-sweep territory (C3 Errors atom dispatcher,
  C4 activity logging, C6 cleanup + `@spec`). Opening them here would
  duplicate work; they're tracked in the Phase 2 plan for this module.

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

- `mix compile --warnings-as-errors` — clean
- `mix format --check-formatted` — clean
- `mix credo --strict` — 0 issues
- `mix dialyzer` — 0 errors (9 skipped via `.dialyzer_ignore.exs`, all
  pre-existing)
- `mix test` — 318 tests, 0 failures (baseline was 316; +2 injection tests)

## Open

- **#11a — FK remap cycle detection.** No demonstrated failure mode; revisit
  during the Wave 2 `connection_notifier.ex` split if the cross-tenant sync
  flow surfaces a cyclic-reference scenario.
- **LiveView-level pinning for `history.ex` and `sender.ex`.** Neither module
  currently has a LiveView test harness in this package — adding one is a C7
  / C10 deliverable in the Phase 2 quality sweep. Until then, the
  `connected?(socket)` guard and the token-based disconnect are verified
  only by compile + manual browser smoke, not by a failing-on-revert test.
