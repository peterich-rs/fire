# iOS Native App

This directory now contains a runnable iOS host shell. The current build uses
`App/FireBindingsShim.swift` under the `FIRE_USE_UNIFFI_STUBS` compilation flag so
the app can build before the generated UniFFI Swift bindings are added.

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
2. Replace `App/FireBindingsShim.swift` with the generated Swift bindings and remove the `FIRE_USE_UNIFFI_STUBS` flag from `project.yml`.
3. Keep the native files in `Sources/FireAppSession/` in the same Xcode target.
4. Create a single `FireSessionStore` instance early in app launch and call `restorePersistedSessionIfAvailable()`.
5. Drive the login `WKWebView` through `FireWebViewLoginCoordinator.completeLogin(from:)`.
6. On explicit logout, call `FireWebViewLoginCoordinator.logout()` and clear any host-side WebView cookies if desired.

Verified local commands:

- `xcodegen generate --spec native/ios-app/project.yml`
- `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build`

Planned responsibilities beyond the current wiring:

- `WKWebView` login and Cloudflare challenge flow
- Cookie extraction and sync into the shared Rust core
- Native navigation, rendering, media integration, and push handling
- Calling Fire Rust bindings through UniFFI-generated Swift APIs
