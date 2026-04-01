# Fire Native Workspace

This repository is the Fire native rebuild workspace.

## Roles

- `references/fluxdo/`
  - keeps the legacy Flutter implementation as a read-only behavior reference
  - remains useful for runtime comparison, but no longer defines the new project structure
- `docs/backend-api*.md`
  - hold the backend protocol notes required for the native rebuild
- `third_party/`
  - stores reusable Rust infrastructure repositories
- `rust/`
  - contains the shared Rust core and the UniFFI boundary
- `native/`
  - contains the iOS and Android native host apps

## Local Layout

```text
fire/
  docs/
    backend-api.md
    backend-api/
    architecture/
      fire-native-workspace.md
  native/
    ios-app/
    android-app/
  references/
    fluxdo/
  rust/
    crates/
      fire-models/
      fire-core/
      fire-uniffi/
  third_party/
    openwire/
    xlog-rs/
```

## Shared Core Boundaries

- Platform-owned:
  - WebView login
  - Cloudflare challenge completion
  - cookie extraction from platform stores
  - native UI, files, media, notifications, keychain/keystore
- Rust-owned:
  - session state
  - bootstrap parsing results
  - API orchestration
  - MessageBus
  - in-app notification state and unread-counter reconciliation
  - shared models
  - logging integration
  - request tracing integration
  - Cloudflare challenge detection

## Dependency Strategy

- `openwire` is the shared Rust network layer, with one shared `Client` per `FireCore` instance now carrying both regular API traffic and MessageBus transport.
- Fire scopes MessageBus-specific execution differences through per-call overrides on that shared client; transport-level HTTP/2 keep-alive remains a shared client policy.
- `mars-xlog` is the shared logging backend.
- `references/fluxdo` is a reference submodule, not a build dependency.
- `third_party/` stores build dependencies as submodules so the superproject can be pushed cleanly to GitHub.
- The root Cargo workspace owns only the local Fire crates.

## Shared Networking Model

- `fire-core` owns one shared `openwire` client per `FireCore` instance.
- Regular API traffic uses the client's default execution policy.
- MessageBus foreground polls and background notification-alert polls use per-call overrides on that same client.
- MessageBus `clientId` remains a Discourse protocol/runtime identity used by subscriptions, presence, and background alert flows; it is not transport ownership.
- Transport-level HTTP/2 keep-alive is a shared client policy, not a per-request toggle.

## Shared Surface

- `fire-models`
  - defines the shared login/session snapshot, notification models, and topic-facing models
- `fire-core`
  - owns session sync, bootstrap parsing, auth refresh/logout, persistence, diagnostics, one shared `openwire` client for API and MessageBus transport, topic list/detail reads, the current reply/reaction write path, the Rust MessageBus poll/subscription runtime, notification fetch/state/mark-read reconciliation, topic-reply presence, and `/topics/timings` request shaping
- `fire-uniffi`
  - exports the shared async API surface, notification list/state APIs, MessageBus callback interface, and error model to Swift/Kotlin
- `native/ios-app` and `native/android-app`
  - host WebView login, cookie capture, native UI state, the current topic browser/detail shells, and thin notification-store wrappers over the shared Rust notification APIs

The intended native integration order is:

1. Open LinuxDo login in `WKWebView` / `WebView`.
2. After login or Cloudflare verification, read platform cookies and the current page HTML/meta.
3. Call `sync_login_context` in Rust with `_t`, `_forum_session`, `cf_clearance`, optional username, CSRF, and homepage HTML.
4. Persist the latest session snapshot through the host-appropriate session policy:
   - iOS writes a redacted `session.json` through `export_redacted_session_json` or `save_redacted_session_to_path` and keeps `_t`, `_forum_session`, and `cf_clearance` in Keychain.
   - Android currently still uses `export_session_json` or `save_session_to_path` until Keystore-backed parity lands.
5. On cold start, restore the snapshot through `restore_session_json` or `load_session_from_path`.
6. Before any authenticated request, hosts that keep auth cookies outside `session.json` must re-inject platform cookies into Rust.
7. If homepage HTML is unavailable or stale, or the restored authenticated snapshot is missing username/shared-session bootstrap fields, call `refresh_bootstrap_if_needed`.
8. If write APIs need a newer token, call `refresh_csrf_token_if_needed`.
9. Use `fetch_topic_list` and `fetch_topic_detail` for the first authenticated read path.
10. On explicit logout, prefer `logout_remote`, then fall back to `logout_local`, clear the persisted session, and remove host-side WebView auth cookies so the native shell and platform browser state agree.
11. Use `notification_state`, `fetch_recent_notifications`, `fetch_notifications`, `mark_notification_read`, and `mark_all_notifications_read` for the shared in-app notification data path; keep OS-level/system notification presentation on the hosts.

File ownership convention:

- Native hosts provide a platform workspace root to Rust:
  - iOS: `Application Support/Fire`
  - Android: `filesDir/fire`
- Rust keeps this workspace root for shared file concerns that belong to the shared layer.
- The current Rust-owned file layout inside that workspace is:
  - `logs/` for Mars Xlog output
  - `diagnostics/fire-readable.log` for a plaintext tracing mirror
  - `cache/xlog/` for Xlog cache and mmap spill files
  - `session.json` for the persisted session snapshot triggered by the host shell
- `session.json` remains host-triggered persistence under that workspace root.
- iOS now treats `session.json` as a redacted cache and stores `_t`, `_forum_session`, and `cf_clearance` in Keychain.
- Android currently still restores the full snapshot from `session.json` until its secure-cookie migration lands.
