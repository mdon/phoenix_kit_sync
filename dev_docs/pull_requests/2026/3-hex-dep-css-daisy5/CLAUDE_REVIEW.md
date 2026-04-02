# PR #3 Review — Fix hex dep, add CSS scanning, update to daisyUI 5 components

**Reviewer:** Claude
**Date:** 2026-04-02
**Verdict:** Approve

---

## Summary

This PR has three distinct changes:

1. **Hex dependency fix:** Changes `phoenix_kit` dependency from `path: "../phoenix_kit"` to `{:phoenix_kit, "~> 1.7"}` in `mix.exs`, switching from local path dependency to Hex package for release readiness.

2. **CSS source scanning:** Adds `css_sources/0` callback implementation returning `[:phoenix_kit_sync]` so the parent app's Tailwind scanner picks up this module's templates.

3. **daisyUI 5 select migration:** Wraps all `<select>` elements across 4 files (connections_live, history, receiver) with the `<label class="select ...">` wrapper pattern. Approximately 8 select elements covering direction/status filters, conflict strategy selects, and table pickers.

Additionally removes two unused `status_badge/1` helper functions and the `@status_colors` module attribute from `connections_live.ex` and `history.ex`.

---

## What Works Well

1. **Hex dep switch.** Moving from path to Hex dependency is correct for publishing. The `~> 1.7` version constraint is appropriate.

2. **CSS sources callback.** Essential for parent apps to scan this module's templates for Tailwind classes. Without this, any Tailwind classes unique to sync templates would be purged in production builds.

3. **Dead code removal.** The `status_badge/1` private functions and `@status_colors` map removed from `connections_live.ex` and `history.ex` appear to be genuinely unused — they were likely superseded by a shared badge component elsewhere.

4. **Select migrations.** All selects across the sync module's 3 LiveView files are consistently wrapped with the daisyUI 5 pattern.

---

## Issues and Observations

### Low: Hex dep version constraint breadth

The `{:phoenix_kit, "~> 1.7"}` constraint will accept any 1.x version >= 1.7.0. If PhoenixKitSync relies on features introduced in a specific minor version (e.g., 1.7.70+), a tighter constraint like `"~> 1.7.70"` would be safer. However, since PhoenixKit follows semantic versioning within the 1.x range, this is acceptable.

### Nit: Removed status_badge functions

The removal of `status_badge/1` from both `connections_live.ex` and `history.ex` is outside the select migration scope but is valid cleanup if these functions are confirmed unused. The compilation would fail if any template still referenced them, so this is safe.

---

## Verdict

**Approve.** Broader scope than the other PRs in this batch, but all three changes are well-motivated: hex dep for publishing, CSS sources for Tailwind scanning, and the consistent daisyUI 5 select migration.
