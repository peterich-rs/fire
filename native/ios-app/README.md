# iOS Native App

Current host-side login wiring lives under `Sources/FireAppSession/`:

- `FireSessionStore.swift`
  - owns `FireCoreHandle`
  - restores persisted session snapshots on cold start
  - persists the latest Rust session snapshot to `Application Support/Fire/session.json`
  - wraps `syncLoginContext`, `refreshBootstrap`, `refreshCsrfToken`, and logout
- `FireWebViewLoginCoordinator.swift`
  - reads `WKWebView` cookies, `current-username`, `csrf-token`, and page HTML
  - converts them into `LoginSyncState`
  - completes login by syncing into Rust and backfilling bootstrap if the page is not reusable

Expected integration flow:

1. Generate the UniFFI Swift bindings from `rust/crates/fire-uniffi`.
2. Add the generated Swift sources and the native files in `Sources/FireAppSession/` to the same Xcode target.
3. Create a single `FireSessionStore` instance early in app launch and call `restorePersistedSessionIfAvailable()`.
4. Drive the login `WKWebView` through `FireWebViewLoginCoordinator.completeLogin(from:)`.
5. On explicit logout, call `FireWebViewLoginCoordinator.logout()` and clear any host-side WebView cookies if desired.

Planned responsibilities beyond the current wiring:

- `WKWebView` login and Cloudflare challenge flow
- Cookie extraction and sync into the shared Rust core
- Native navigation, rendering, media integration, and push handling
- Calling Fire Rust bindings through UniFFI-generated Swift APIs
