# Android Native App

This directory now contains a runnable Android host shell. The current build uses
`src/main/java/uniffi/fire_uniffi/FireBindingsStub.kt` so the app can launch before
the generated UniFFI Kotlin bindings are wired in.

Current host-side login wiring lives under `src/main/java/com/fire/app/session/`:

- `FireSessionStore.kt`
  - owns `FireCoreHandle`
  - passes the platform workspace root (`filesDir/fire`) into Rust during initialization
  - restores persisted session snapshots on cold start
  - persists the latest Rust session snapshot to `filesDir/fire/session.json`
  - lets Rust initialize shared logs under `filesDir/fire/logs`
  - wraps `syncLoginContext`, `refreshBootstrap`, `refreshCsrfToken`, and logout
- `FireWebViewLoginCoordinator.kt`
  - reads `WebView` cookies, `current-username`, `csrf-token`, and page HTML
  - converts them into `LoginSyncState`
  - completes login by syncing into Rust and backfilling bootstrap if the page is not reusable
- `LoginActivity.kt`
  - presents login as a full-screen activity with visible page title, URL, and loading state
  - exposes back, forward, home, and reload controls
  - routes the system back button to `WebView.goBack()` before closing the activity
  - enables third-party cookies and DOM storage so OAuth-style login hops can round-trip cleanly

Expected integration flow:

1. Generate the UniFFI Kotlin bindings from `rust/crates/fire-uniffi`.
2. Replace `src/main/java/uniffi/fire_uniffi/FireBindingsStub.kt` with the generated bindings.
3. Keep the files in `src/main/java/com/fire/app/session/` in the same Android module.
4. Create a single `FireSessionStore` instance during app startup and call `restorePersistedSessionIfAvailable()`.
5. Drive the login `WebView` through `FireWebViewLoginCoordinator.completeLogin(webView)`.
6. On explicit logout, call `FireWebViewLoginCoordinator.logout()` and clear host-side `CookieManager` entries if desired.

Workspace note:

- The Android host now passes `filesDir/fire` into Rust as the workspace root.
- Rust now initializes shared logging under `filesDir/fire/logs` and keeps xlog cache files under `filesDir/fire/cache/xlog`.
- Rust can resolve relative paths inside that workspace for shared file ownership such as logs, caches, or exports.
- The current persisted session file remains `filesDir/fire/session.json`.

Note:

- The Kotlin files assume the generated bindings use the `uniffi.fire_uniffi` package. If your UniFFI generation step uses a different namespace, adjust the imports.
- Build with a full JDK that includes `jlink`. On this machine, `JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ./gradlew assembleDebug` is verified working.
- Android does not have an iOS-style runtime "internet permission" prompt for ordinary web access. `android.permission.INTERNET` is a normal install-time permission, so there is no separate network-permission preflight to mirror.

Planned responsibilities beyond the current wiring:

- `WebView` login and Cloudflare challenge flow
- Cookie extraction and sync into the shared Rust core
- Native navigation, rendering, media integration, and notification handling
- Calling Fire Rust bindings through UniFFI-generated Kotlin APIs
