# Fire Native Workspace

This repository is now the root of the Fire native rebuild.

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

- `openwire` is the shared Rust network layer.
- `mars-xlog` is the shared logging backend.
- `references/fluxdo` is a reference submodule, not a build dependency.
- `third_party/` stores build dependencies as submodules so the superproject can be pushed cleanly to GitHub.
- The root Cargo workspace owns only the local Fire crates.

## Shared Surface

- `fire-models`
  - defines the shared login/session snapshot, notification models, and topic-facing models
- `fire-core`
  - owns session sync, bootstrap parsing, auth refresh/logout, persistence, diagnostics, topic list/detail reads, the current reply/reaction write path, the Rust MessageBus poll/subscription runtime, and the shared notification fetch/state/mark-read reconciliation layer
- `fire-uniffi`
  - exports the shared async API surface, notification list/state APIs, MessageBus callback interface, and error model to Swift/Kotlin
- `native/ios-app` and `native/android-app`
  - host WebView login, cookie capture, native UI state, the current topic browser/detail shells, and thin notification-store wrappers over the shared Rust notification APIs

The intended native integration order is:

1. Open LinuxDo login in `WKWebView` / `WebView`.
2. After login or Cloudflare verification, read platform cookies and the current page HTML/meta.
3. Call `sync_login_context` in Rust with `_t`, `_forum_session`, `cf_clearance`, optional username, CSRF, and homepage HTML.
4. Persist the latest session snapshot through `export_session_json` or `save_session_to_path`.
5. On cold start, restore the snapshot through `restore_session_json` or `load_session_from_path`.
6. If homepage HTML is unavailable or stale, or the restored authenticated snapshot is missing username/shared-session bootstrap fields, call `refresh_bootstrap_if_needed`.
7. If write APIs need a newer token, call `refresh_csrf_token_if_needed`.
8. Use `fetch_topic_list` and `fetch_topic_detail` for the first authenticated read path.
9. On explicit logout, prefer `logout_remote`, then fall back to `logout_local`, clear the persisted session, and remove host-side WebView auth cookies so the native shell and platform browser state agree.
10. Use `notification_state`, `fetch_recent_notifications`, `fetch_notifications`, `mark_notification_read`, and `mark_all_notifications_read` for the shared in-app notification data path; keep OS-level/system notification presentation on the hosts.

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
- The current session snapshot remains host-triggered persistence under `session.json` inside that workspace root.

## Current MessageBus Status

- The shared Rust/UniFFI MessageBus foundation is now in place:
  - Rust owns the foreground poll/subscription runtime, bootstrap tracking-channel registration, cross-origin `X-Shared-Session-Key` handling, and typed event classification for topic-list, topic-detail, topic-reaction, topic-reply-presence, notification, and notification-alert channels.
  - Rust now owns `/notifications` recent/full-list fetch, pagination cursors, mark-read flows, unread counters, and recent/full-list reconciliation.
  - MessageBus `/notification/{userId}` payloads now merge unread counts, recent read-state updates, and new-notification inserts into the shared notification runtime.
  - Rust now owns topic-reply Presence bootstrap (`GET /presence/get`) plus active-client presence heartbeats (`POST /presence/update`) on top of the current foreground MessageBus `clientId`.
  - Rust now also owns `/topics/timings` request shaping plus a one-shot `/notification-alert/{userId}` polling surface for iOS background refresh runs.
- Host integration status:
  - iOS now auto-starts the foreground MessageBus, refreshes topic list/detail state on matching events, subscribes topic detail reaction and presence channels, syncs the notification list from shared notification state, reports topic reading timings, and surfaces topic-reply presence above the quick-reply bar.
  - iOS now also schedules `BGAppRefreshTask` runs that restore the persisted Rust session, perform a one-shot shared `/notification-alert/{userId}` poll with a temporary background `clientId`, and present host-owned local notifications.
  - Android currently exposes the shared notification APIs through its session-store wrapper, but does not yet wire live MessageBus host behavior.
  - OS-level/system notification presentation remains host-owned; Rust currently stops at event delivery plus the background alert polling primitive.

## Next Delivery Priorities

- P2: Move login cookie persistence into platform-secured storage.
  - Keep `_t` / `_forum_session` in Keychain or Keystore backed storage and inject them back into Rust on startup.
  - Stop treating `session.json` as the durable home for raw auth cookies once the secured platform storage path exists; keep only non-secret bootstrap/session data there, and require the host to re-inject platform cookies before authenticated reads, writes, or MessageBus startup after a cold launch.
- P3: Add shared search APIs plus the first native search UI.
  - Cover `/search.json`, tag search, and mention autocomplete in Rust.
  - Start with iOS search entry, filter builder, and result views; Android can follow the same Rust surface afterward.
- P4: Extend the shared write path into a full composer pipeline.
  - Add upload, draft, and create-topic APIs in Rust, reusing the shared foreground `clientId`.
  - Build the iOS composer with title, category, tags, upload progress, draft recovery, and mention autocomplete.
- P5: Add user profile and social relationship surfaces.
  - Implement shared user detail, summary, follow graph, follow/unfollow, and bookmark APIs in Rust.
  - Add native entry points from topic author taps into profile and bookmark screens.
- P6: Finish Presence and reading-timing reporting on top of the shared `clientId`.
  - The shared Rust/iOS foreground Presence path, `/topics/timings` reporting, and the iOS background `notification-alert` chain are now in place.
  - Remaining work is Android host integration plus any notification tap-through/deep-link follow-up on the native hosts.
- P7: Deepen cooked-post rendering on both native hosts.
  - Prioritize poll UI, syntax-highlighted code blocks, richer quote/table/spoiler handling, and parity between the iOS and Android renderers.
  - Keep cooked-module rendering host-owned even when the backing fetch and mutation APIs live in Rust.

Current dependency order:

- P2 is independent of the completed shared notification layer and can run in parallel with host-side notification UI work.
- The Rust MessageBus surface now unlocks the completed shared notification layer, the shared `clientId` requirement in P4 uploads, and P6 Presence.
- P3 is independent, but P4 should wait for its mention-autocomplete surface.
- P7 should stay host-owned and layer on top of the topic-detail rendering stack instead of reopening shared API ownership.

Deferred but still open:

- Decide whether iOS generated build outputs should remain project-local under `Generated/` or move into a reusable package/XCFramework distribution path for CI and release workflows.
