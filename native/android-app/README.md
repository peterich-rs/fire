# Android Native App

Current host-side login wiring lives under `src/main/java/com/fire/app/session/`:

- `FireSessionStore.kt`
  - owns `FireCoreHandle`
  - restores persisted session snapshots on cold start
  - persists the latest Rust session snapshot to `filesDir/fire/session.json`
  - wraps `syncLoginContext`, `refreshBootstrap`, `refreshCsrfToken`, and logout
- `FireWebViewLoginCoordinator.kt`
  - reads `WebView` cookies, `current-username`, `csrf-token`, and page HTML
  - converts them into `LoginSyncState`
  - completes login by syncing into Rust and backfilling bootstrap if the page is not reusable

Expected integration flow:

1. Generate the UniFFI Kotlin bindings from `rust/crates/fire-uniffi`.
2. Add the generated Kotlin sources and the files in `src/main/java/com/fire/app/session/` to the same Android module.
3. Create a single `FireSessionStore` instance during app startup and call `restorePersistedSessionIfAvailable()`.
4. Drive the login `WebView` through `FireWebViewLoginCoordinator.completeLogin(webView)`.
5. On explicit logout, call `FireWebViewLoginCoordinator.logout()` and clear host-side `CookieManager` entries if desired.

Note:

- The Kotlin files assume the generated bindings use the `uniffi.fire_uniffi` package. If your UniFFI generation step uses a different namespace, adjust the imports.

Planned responsibilities beyond the current wiring:

- `WebView` login and Cloudflare challenge flow
- Cookie extraction and sync into the shared Rust core
- Native navigation, rendering, media integration, and notification handling
- Calling Fire Rust bindings through UniFFI-generated Kotlin APIs
