# iOS Native App

This directory now contains a runnable iOS host shell. The current build uses
`App/FireBindingsShim.swift` under the `FIRE_USE_UNIFFI_STUBS` compilation flag so
the app can build before the generated UniFFI Swift bindings are added.

Current host-side login wiring lives under `Sources/FireAppSession/`:

- `FireSessionStore.swift`
  - owns `FireCoreHandle`
  - passes the platform workspace root (`Application Support/Fire`) into Rust during initialization
  - restores persisted session snapshots on cold start
  - persists the latest Rust session snapshot to `Application Support/Fire/session.json`
  - lets Rust initialize shared logs under `Application Support/Fire/logs`
  - wraps `syncLoginContext`, `refreshBootstrap`, `refreshCsrfToken`, and logout
- `FireWebViewLoginCoordinator.swift`
  - reads `WKWebView` cookies, `current-username`, `csrf-token`, and page HTML
  - converts them into `LoginSyncState`
  - completes login by syncing into Rust and backfilling bootstrap if the page is not reusable
- `App/FireLoginWebView.swift`
  - presents the login browser as a full-screen flow
  - exposes back, forward, home, and reload controls so OAuth hops can return to LinuxDo without closing the sheet
  - enables back/forward swipe gestures on the embedded `WKWebView`
- `App/FireAppViewModel.swift`
  - performs a lightweight network preflight before presenting the login browser
  - moves the first system-level network prompt, when one appears on-device, out of the login page itself

Expected integration flow:

1. Generate the UniFFI Swift bindings from `rust/crates/fire-uniffi`.
2. Replace `App/FireBindingsShim.swift` with the generated Swift bindings and remove the `FIRE_USE_UNIFFI_STUBS` flag from `project.yml`.
3. Keep the native files in `Sources/FireAppSession/` in the same Xcode target.
4. Create a single `FireSessionStore` instance early in app launch and call `restorePersistedSessionIfAvailable()`.
5. Drive the login `WKWebView` through `FireWebViewLoginCoordinator.completeLogin(from:)`.
6. On explicit logout, call `FireWebViewLoginCoordinator.logout()` and clear any host-side WebView cookies if desired.

Workspace note:

- The iOS host now passes `Application Support/Fire` into Rust as the workspace root.
- Rust now initializes shared logging under `Application Support/Fire/logs` and keeps xlog cache files under `Application Support/Fire/cache/xlog`.
- Rust can resolve relative paths inside that workspace for shared file ownership such as logs, caches, or exports.
- The current persisted session file remains `Application Support/Fire/session.json`.

Current UX note:

- The app now opens login as a full-screen browser instead of a partial sheet.
- The login browser can navigate back from Google or other intermediate pages without forcing the user to close and reopen login.
- The network preflight is a best-effort connectivity warm-up. iOS does not provide a generic "internet permission" API for arbitrary web access, so this only shifts the first prompt/request earlier; it does not create a separate permission flow.

Verified local commands:

- `xcodegen generate --spec native/ios-app/project.yml`
- `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build`

Planned responsibilities beyond the current wiring:

- `WKWebView` login and Cloudflare challenge flow
- Cookie extraction and sync into the shared Rust core
- Native navigation, rendering, media integration, and push handling
- Calling Fire Rust bindings through UniFFI-generated Swift APIs
