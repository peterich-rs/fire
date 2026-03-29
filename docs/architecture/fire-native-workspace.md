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
  - contains the future iOS and Android native host apps

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
  - shared models
  - logging integration
  - request tracing integration

## Dependency Strategy

- `openwire` is the shared Rust network layer.
- `mars-xlog` is the shared logging backend.
- `references/fluxdo` is a reference submodule, not a build dependency.
- `third_party/` stores build dependencies as submodules so the superproject can be pushed cleanly to GitHub.
- The root Cargo workspace owns only the local Fire crates.

## Current Login Pipeline

The first usable session pipeline now lives in the Rust workspace:

- `fire-models`
  - defines the shared login/session snapshot
  - tracks auth cookies, CSRF, bootstrap artifacts, login phase, and session readiness
- `fire-core`
  - merges platform-synced cookies from iOS/Android WebView
  - parses homepage HTML for `csrf-token`, `shared_session_key`, `discourse-base-uri`, `data-preloaded`, and Turnstile `sitekey`
  - derives `currentUser.username`, `siteSettings.long_polling_base_url`, and `topicTrackingStateMeta` from `data-preloaded`
  - exposes network-backed `refresh_bootstrap`, `refresh_csrf_token`, `logout_remote`, and local `logout_local`
  - can export/import persisted session JSON and save/load session snapshots from disk for cold-start restoration
  - keeps an in-process request trace timeline for every Rust-owned HTTP call, including execution-chain events, headers, and captured response bodies
  - exposes workspace log file listing/reading, including the readable tracing mirror under `diagnostics/`
  - exposes authenticated topic list and topic detail fetching for `latest/new/unread/unseen/hot/top` plus tracked topic detail requests
  - retries one logout request on `BAD CSRF` after refreshing `/session/csrf`
- `fire-uniffi`
  - exports the session snapshot, readiness flags, login sync input, bootstrap sync APIs, persistence APIs, diagnostics APIs, topic APIs, and logout APIs to Swift/Kotlin
  - now exposes network-backed APIs as native async UniFFI methods for Swift/Kotlin instead of re-wrapping them as synchronous FFI calls
  - now keeps exported platform interactions on `Result`-style error paths so Rust panics are logged, returned as `Internal` UniFFI errors, and poison the current handle for subsequent calls
  - keeps binding configuration in `rust/crates/fire-uniffi/uniffi.toml`
- `native/ios-app` and `native/android-app`
  - now drive a minimal latest-topic list plus topic detail shell on top of the exported topic API surface
  - now surface native diagnostics screens for workspace logs plus request-trace overview/detail views
  - now build against generated UniFFI bindings in app builds, with Android packaging `.so` libraries and iOS linking a generated Rust static library

The intended native integration order is:

1. Open LinuxDo login in `WKWebView` / `WebView`.
2. After login or Cloudflare verification, read platform cookies and the current page HTML/meta.
3. Call `sync_login_context` in Rust with `_t`, `_forum_session`, `cf_clearance`, optional username, CSRF, and homepage HTML.
4. Persist the latest session snapshot through `export_session_json` or `save_session_to_path`.
5. On cold start, restore the snapshot through `restore_session_json` or `load_session_from_path`.
6. If homepage HTML is unavailable or stale, call `refresh_bootstrap`.
7. If write APIs need a newer token, call `refresh_csrf_token`.
8. Use `fetch_topic_list` and `fetch_topic_detail` for the first authenticated read path.
9. On explicit logout, prefer `logout_remote`, then fall back to `logout_local`, and clear the persisted session.

The current host shells now cover that first read path at the UI layer, and both app targets now compile against generated UniFFI outputs.

Current file ownership convention:

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

The Android host shell now generates Kotlin UniFFI bindings at build time, packages Rust-backed Android `.so` libraries per build variant, and renders the topic browser against the real shared Rust core. The iOS host shell now does the same at build time for Swift bindings plus a Rust static library and links that output directly into the Xcode target, while keeping the host bindgen step isolated from Xcode's iPhone SDK environment.
Both native hosts now keep feed pagination state, derive category metadata from bootstrap `data-preloaded.site.categories`, and render richer topic/detail metadata on top of the shared Rust topic APIs. The iOS host has now moved past the developer-style `List` shell into a more formal SwiftUI workspace with a session gate, feed console, spotlight topic paging, dense thread scanning, adaptive light/dark theming, and full-screen login chrome, while Android topic detail already opens in a dedicated native screen. Both native hosts currently flatten cooked post HTML to safer plain text until a structured module-aware renderer is implemented.

## Next Build Steps

1. Continue expanding the current Android/iOS topic browser shells with avatar/media handling, category/user navigation, and richer interaction models on top of the existing topic API layer.
2. Add MessageBus client orchestration on top of restored `shared_session_key` / `topicTrackingStateMeta`.
3. Move platform cookie storage into keychain/keystore backed persistence and reconcile it with the Rust snapshot lifecycle.
4. Decide whether iOS build outputs should stay project-local under `Generated/` or be elevated into a reusable package/XCFramework flow for distribution and CI caching.
