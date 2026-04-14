# iOS Beta APM Foundation

This document describes the iOS-only crash and APM runtime added for the beta phase.

## Scope

- Crash capture uses `PLCrashReporter` from the native host.
- System metrics and delayed diagnostics use `MetricKit`.
- SwiftUI route correlation, launch spans, topic/detail/reply/notification spans, and main-thread stall tracking stay on the iOS side.
- Shared Rust diagnostics, logs, request traces, and MessageBus networking remain Rust-owned.

## Runtime layout

- Workspace root remains `Application Support/Fire`.
- New iOS-owned APM data lives under `Application Support/Fire/ios-apm/`.
- Current subdirectories:
  - `events/` daily NDJSON event files
  - `crashes/` raw `.plcrash` payloads
  - `metrickit/` raw MetricKit JSON payloads
  - `runtime-states/` per-launch route / scene / breadcrumb snapshots
  - `tmp/` PLCrashReporter and full-export staging files
- Shareable full-export artifacts live under `Application Support/Fire/ios-apm-exports/` as `.zip` archives.
- The app keeps at most the latest 3 full-export archives and expires archives older than 24 hours.

## Correlation model

- Each host launch generates a `launch_id`.
- When `FireSessionStore` becomes available, the iOS APM runtime fetches Rust `diagnostic_session_id` and records a `session_link` event.
- Crash harvest on the next cold start uses the previous `runtime-state.json` to recover the last known route, scene phase, active spans, and breadcrumbs.
- Host-owned APM files are not written back into Rust diagnostics directories.

## Export and release workflow

- Standard diagnostics export still comes from Rust via `export_support_bundle`.
- Full iOS APM export creates a `.zip` archive whose root folder preserves the `.firesupportbundle` layout and contains:
  - Rust support bundle copy, when available
  - iOS APM events
  - raw crash payloads
  - raw MetricKit payloads
  - APM manifest with build metadata
- Export staging directories are removed immediately after zipping so only the final archive remains in `ios-apm-exports/`.
- Release artifact generation is handled by `scripts/ios/archive_release.sh`.
- CI/manual archive artifact generation is handled by `.github/workflows/ios-release-artifacts.yml`.
- The archive script injects `FIRE_GIT_SHA`, archives the app, copies `dSYMs/`, and emits `build-metadata.json`.

## Privacy rules

- Crash, MetricKit, route, span, breadcrumb, and resource sample metadata are retained for beta diagnostics.
- `Cookie`, `Set-Cookie`, `Authorization`, `X-CSRF-Token`, and Keychain contents are never persisted into iOS APM artifacts.
- The iOS runtime may reference Rust trace summaries indirectly through the shared diagnostics surface later, but it does not duplicate shared request bodies.
