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
  - crash capture and host-owned APM collection
  - native UI, files, media, notifications, keychain/keystore
- Rust-owned:
  - session state
  - session persistence revision tracking for snapshot/auth-cookie writes
  - session epoch invalidation for stale network responses and cookies
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

## Clean Worktree Workflow

- The repository root may temporarily carry owner-only `openwire` experiments; do not assume the root checkout itself is the delivery baseline.
- The delivery baseline is always the latest `main`, after `git fetch origin` and a fast-forward update to `origin/main`.
- Standard feature work should start from a clean secondary worktree under `../fire-worktrees/`, branched from that updated `main`.
- The current mainline baseline must keep `third_party/openwire` and `third_party/xlog-rs` initialized, clean, and pinned to reviewed commits.
- CI and local verification should fail fast when those required submodules are missing local checkout state, have local modifications, or have uncommitted pointer drift in the superproject.
- Before integrating a long-lived feature branch back to main, first sync it with the latest `main`, then validate the final result from a clean `main` worktree.

## Shared Networking Model

- `fire-core` owns one shared `openwire` client per `FireCore` instance.
- Regular API traffic uses the client's default execution policy.
- MessageBus foreground polls and background notification-alert polls use per-call overrides on that same client.
- MessageBus `clientId` remains a Discourse protocol/runtime identity used by subscriptions, presence, and background alert flows; it is not transport ownership.
- Fire’s local MessageBus runtime separately tracks subscription ownership with per-subscriber owner tokens so overlapping native lifecycles can share one polled channel set without tearing each other down.
- Transport-level HTTP/2 keep-alive is a shared client policy, not a per-request toggle.

## Shared Surface

- `fire-models`
  - defines the shared login/session snapshot, notification models, and topic/private-message-facing models
- `fire-core`
  - owns session sync, bootstrap parsing, auth refresh/logout, persistence, diagnostics, one shared `openwire` client for API and MessageBus transport, topic list/detail reads (including category/tag scoped lists and private-message mailboxes), reply/reaction/topic/private-message write paths, draft APIs, upload APIs, the Rust MessageBus poll/subscription runtime, notification fetch/state/mark-read reconciliation, topic-reply presence, and `/topics/timings` request shaping
  - finalizes network traces in Rust with terminal outcomes (`Succeeded`, `Failed`, or `Cancelled`); hosts should treat timeline events as intermediate diagnostics instead of completion signals
- `fire-uniffi`
  - exports the shared async API surface, notification list/state APIs, MessageBus callback interface, and error model to Swift/Kotlin
- `native/ios-app` and `native/android-app`
  - host WebView login, cookie capture, native UI state, the current topic browser/detail shells, native composer/private-message UX, and thin notification-store wrappers over the shared Rust notification APIs
  - iOS topic-detail state is retained by per-view owner tokens while a detail screen is active, so background homepage refreshes can no longer evict an on-screen topic detail cache
  - iOS now keeps a host-only prepared topic-detail render cache and coalesces MessageBus ingress before MainActor delivery, while leaving session/runtime ownership with Rust

The intended native integration order is:

1. Open LinuxDo login in `WKWebView` / `WebView`.
2. After login or Cloudflare verification, read the platform cookie store, the current page HTML/meta, and the live WebView/browser user agent.
3. Call `sync_login_context` in Rust with the full same-site browser cookie batch, optional username, CSRF, the preferred homepage HTML captured through the browser context, and the WebView/browser user agent.
4. Persist the latest session snapshot through the host-appropriate session policy:
  - iOS currently writes the full `session.json` snapshot during the active diagnostics-heavy development phase, keeps the full same-site browser cookie batch in Keychain with expiry metadata and distinct host/domain variants, and now gates both writes off Rust-owned snapshot/auth-cookie persistence revisions instead of diffing exported session JSON in Swift.
   - Android currently uses `export_session_json` or `save_session_to_path` until Keystore-backed parity lands.
5. On cold start, restore the snapshot through `restore_session_json` or `load_session_from_path`.
6. Before any authenticated request, hosts that keep browser cookies outside `session.json` must re-inject that platform cookie batch into Rust.
7. If homepage HTML is unavailable or stale, or the restored authenticated snapshot is missing username/preloaded bootstrap fields, call `refresh_bootstrap_if_needed`. When homepage bootstrap still lacks site metadata such as categories/top tags, the shared Rust layer now falls back to `/site.json`. Only treat `shared_session_key` as required when MessageBus uses a cross-origin long-polling host.
8. If the restored session is otherwise ready but the local snapshot still lacks CSRF, call `refresh_csrf_token_if_needed` before surfacing a fully ready authenticated session. The iOS `restoreColdStartSession()` path now performs this repair automatically. Write APIs can reuse the same helper whenever they need a newer token.
9. Use `fetch_topic_list` (global, category-scoped, tag-scoped, or private-message mailbox variants via `TopicListQuery`) and `fetch_topic_detail` for the authenticated read paths.
10. If Rust returns `CloudflareChallenge` for an authenticated operation, keep the current session snapshot, present `/challenge` in a host-owned auth WebView, re-sync the latest same-site browser cookie batch into Rust after verification, and then retry the blocked operation from the host.
11. On explicit logout, prefer `logout_remote`, then fall back to `logout_local`, clear the persisted session, and remove host-side WebView auth cookies so the native shell and platform browser state agree.
12. Use `notification_state`, `fetch_recent_notifications`, `fetch_notifications`, `mark_notification_read`, and `mark_all_notifications_read` for the shared in-app notification data path; keep OS-level/system notification presentation on the hosts.

File ownership convention:

- Native hosts provide a platform workspace root to Rust:
  - iOS: `Application Support/Fire`
  - Android: `filesDir/fire`
- Rust keeps this workspace root for shared file concerns that belong to the shared layer.
- The current Rust-owned file layout inside that workspace is:
  - `logs/` for Mars Xlog output
  - `diagnostics/fire-readable.log` for a plaintext tracing mirror
  - `diagnostics/support-bundles/` for locally exported diagnostics bundles
  - `cache/xlog/` for Xlog cache and mmap spill files
  - `session.json` for the persisted session snapshot triggered by the host shell
- iOS now also owns `ios-apm/` under the same workspace root for beta crash/APM files. That directory is explicitly host-owned and must not be treated as shared Rust diagnostics state.
- Debug builds may also mirror shared logs into the platform console for local development, but release builds keep shared logging file-only through Xlog/readable-log artifacts.
- `session.json` remains host-triggered persistence under that workspace root.
- iOS currently treats `session.json` as a full-fidelity development cache and stores the same-site browser cookie batch in Keychain, including expiry metadata and refreshed auth-cookie state observed by Rust, while letting Rust-owned persistence revisions decide when those writes are actually necessary.
- Android currently still restores the full snapshot from `session.json` until its secure-cookie migration lands.
