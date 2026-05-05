## 0.1.2 - 2026-05-05

### Changed
- Test schema setup now uses `PhoenixKit.Migration.ensure_current/2` (requires
  `phoenix_kit` 1.7.105+) instead of hand-rolled inline DDL — eliminates schema
  drift between test and production by construction.

### Fixed
- LiveView Iron Law: `ConnectionsLive.mount/3` no longer queries the DB during
  the HTTP dead render; `load_connections/1` is gated on `connected?(socket)`.
- LiveView Iron Law: `ConnectionsLive.handle_params/3` `show`/`edit`/`sync`
  branches no longer query the DB during the dead render of deep-linked URLs.
- F4 revoke gettext test now correctly mounts into the connection detail view
  (where the revoke button lives) via deep-link URL.

## 0.1.1 - 2026-04-11

### Fixed
- Add routing anti-pattern warning to AGENTS.md

## 0.1.0 - 2026-03-21

### Added
- Initial release of PhoenixKitSync as a standalone package
- Peer-to-peer data sync between PhoenixKit instances (dev-prod, dev-dev, cross-site)
- WebSocket-based real-time data transfer with session codes and permanent token auth
- Permanent connections with access controls (IP whitelist, allowed hours, download/record limits)
- Transfer history with approval workflow (auto-approve, require-approval, per-table)
- Conflict resolution strategies: skip, overwrite, merge, append
- Background import via Oban workers with batched processing
- Database schema introspection and table discovery
- LiveView UI for connections management, transfer history, sender/receiver flows
- API endpoint for automatic cross-site connection registration
- Programmatic API for scripted and AI-agent-driven sync operations
