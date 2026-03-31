# Post-Merge Follow-up for PR #2

**Review Date:** 2026-03-27  
**Reviewed By:** Claude  
**Status:** Issues identified for future fixes

This document captures issues discovered during post-merge code review of PR #2. These items should be addressed in follow-up commits or PR #3.

---

## Critical Issues

### 1. Unsupervised `Task.start` calls cause resource leak (HIGH)

**Files:** `lib/phoenix_kit_sync/web/connections_live.ex`  
**Lines:** 190, 224, 307, 330, 352, 375, 412, 718, 759, 798, 846, 939

All async HTTP notifications use `Task.start/1` (unlinked, unsupervised). If the HTTP call hangs at the 30s timeout, orphaned processes accumulate. Each LiveView mount also spawns N tasks via `fetch_sender_statuses` and `verify_receiver_connections`.

**Impact:** Memory leak under sustained use; unobservable failures (no crash reports); potential for process exhaustion under heavy admin traffic.

**Current code:**
```elixir
# Line 307
Task.start(fn ->
  ConnectionNotifier.notify_status_change(updated_connection, "active")
end)
```

**Recommended fix:** Use `Task.Supervisor.start_child/2`:

```elixir
Task.Supervisor.start_child(PhoenixKit.TaskSupervisor, fn ->
  ConnectionNotifier.notify_status_change(updated_connection, "active")
end)
```

---

## Architecture Issues

### 2. `connection_created` PubSub handler amplifies HTTP traffic (MEDIUM)

**File:** `lib/phoenix_kit_sync/web/connections_live.ex:1060-1062`

```elixir
def handle_info({:connection_created, _connection_uuid}, socket) do
  {:noreply, load_connections(socket)}  # no skip_async — spawns HTTP tasks
end
```

Unlike other PubSub handlers, `connection_created` runs full `load_connections/1` including HTTP calls. Every LiveView session spawns N tasks per new connection event.

**Impact:** HTTP thundering herd during bulk connection creation.

**Fix:** Add `skip_async: true` for PubSub-triggered reloads.

---

### 3. `parse_decimal_string` matches too broadly — data corruption risk (MEDIUM)

**File:** `lib/phoenix_kit_sync/connection_notifier.ex:1640-1647`

```elixir
@decimal_regex ~r/^-?\d+\.\d+$/
defp parse_decimal_string(value) do
  if Regex.match?(@decimal_regex, value), do: Decimal.new(value)
end
```

Applied to **all** string values regardless of target column type. A `text` column containing `"3.14"` (version number) gets converted to `%Decimal{}`, which Postgrex will try to bind as numeric — failing on varchar/text columns.

**Fix:** Use column type metadata from `SchemaInspector` to only parse decimals when target column is `numeric`/`decimal`.

---

## Code Quality Issues

### 4. `changed_fields` detection uses atom-key comparison (MEDIUM)

**File:** `lib/phoenix_kit_sync/connections.ex:298-301`

```elixir
attrs
|> Enum.reject(fn {k, v} -> Map.get(connection, k) == v end)
```

`Map.get(connection, k)` only works for atom keys. When `attrs` come from LiveView (string keys), every field appears "changed".

**Fix:** Normalize keys before comparison using `String.to_existing_atom/1`.

---

### 5. Error struct shape assumption in `notify_delete` (LOW)

**File:** `lib/phoenix_kit_sync/connection_notifier.ex:248`

```elixir
{:error, %{reason: reason}} when reason in [:econnrefused, :timeout, :nxdomain] ->
```

Assumes HTTP client error is always a map with `:reason` key.

**Fix:** Add defensive pattern matching for `Mint.TransportError` structs.

---

### 6. Missing `@spec` declarations (LOW)

Several public functions in `Connections` and `ConnectionNotifier` lack `@spec` declarations, hurting Dialyzer analysis.

---

## Action Items

| Priority | Issue | Action | Owner |
|----------|-------|--------|-------|
| HIGH | #1 Unsupervised tasks | Switch to `Task.Supervisor` | TBD |
| HIGH | #2 HTTP amplification | Add `skip_async: true` | TBD |
| HIGH | #3 Decimal parsing | Use column type metadata | TBD |
| MEDIUM | #4 `changed_fields` | Normalize keys | TBD |
| LOW | #5 Error patterns | Add defensive clauses | TBD |
| LOW | #6 Missing specs | Add `@spec` to public functions | TBD |

---

*Related: Original review in `CLAUDE_REVIEW.md`*
