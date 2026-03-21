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
