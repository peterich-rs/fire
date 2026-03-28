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
  - exposes authenticated topic list and topic detail fetching for `latest/new/unread/unseen/hot/top` plus tracked topic detail requests
  - retries one logout request on `BAD CSRF` after refreshing `/session/csrf`
- `fire-uniffi`
  - exports the session snapshot, readiness flags, login sync input, bootstrap sync APIs, persistence APIs, topic APIs, and logout APIs to Swift/Kotlin

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

## Next Build Steps

1. Create the Swift and Kotlin host apps under `native/` and wire them to the exported session APIs.
2. Build the authenticated topic list / topic detail API layer on top of the current session pipeline.
3. Add MessageBus client orchestration on top of restored `shared_session_key` / `topicTrackingStateMeta`.
4. Move platform cookie storage into keychain/keystore backed persistence and reconcile it with the Rust snapshot lifecycle.
