# Android Native App

This directory now contains a runnable Android host shell. The current build
generates Kotlin UniFFI bindings at build time and packages Rust-backed Android
shared libraries for the app to load through JNA.

Current host-side app wiring lives under `src/main/java/com/fire/app/` plus `src/main/java/com/fire/app/session/`:

- `FireSessionStore.kt`
  - owns `FireCoreHandle`
  - passes the platform workspace root (`filesDir/fire`) into Rust during initialization
  - restores persisted session snapshots on cold start
  - persists the latest Rust session snapshot to `filesDir/fire/session.json`
  - lets Rust initialize shared logs under `filesDir/fire/logs`
  - wraps `syncLoginContext`, `refreshBootstrap`, `refreshCsrfToken`, diagnostics reads, topic fetches, and logout
- `scripts/sync_uniffi_bindings.sh`
  - builds an unstripped host debug library for UniFFI metadata extraction
  - reads generator settings from `rust/crates/fire-uniffi/uniffi.toml`
  - generates Kotlin bindings from `fire-uniffi`
  - cross-compiles `libfire_uniffi.so` for `arm64-v8a` and `x86_64`
  - resolves the host-side UniFFI metadata library extension per OS so Gradle sync can run on macOS and Linux CI
  - keeps release Android `.so` packaging separate from host bindgen input so Linux CI is not broken by the workspace `strip = true` release profile
  - writes variant-specific generated sources and JNI libraries into the Gradle build directory
- `FireWebViewLoginCoordinator.kt`
  - reads the current `WebView` cookie batch, `current-username`, `csrf-token`, page HTML, and the live browser user agent
  - converts them into `LoginSyncState`
  - completes login by syncing into Rust and backfilling bootstrap if the page is not reusable
- `TopicPresentation.kt`
  - extracts `site.categories` from bootstrap `preloadedJson`
  - parses `more_topics_url` into a native feed page cursor
  - normalizes topic/post timestamps for inline rendering
- `MainActivity.kt`
  - restores the persisted session snapshot on launch and after login
  - renders a paginated topic browser with feed filters, category-aware Rust-owned topic rows, and a focused selected-topic summary
  - opens topic detail in a dedicated screen instead of fetching and rendering it inline in the feed host
- `DiagnosticsActivity.kt`, `LogViewerActivity.kt`, `RequestTraceDetailActivity.kt`
  - surface a native diagnostics entry point
  - list readable/shared log files from the Rust workspace
  - render a reverse-chronological request trace overview and per-request execution-chain/detail pages
- `TopicDetailActivity.kt`
  - loads topic detail on demand from the shared Rust API
  - renders the original post plus Rust-generated flat thread posts in a dedicated native screen
  - renders cooked post bodies through shared Rust plain-text helpers while topic-detail HTML module handling is still pending
- `LoginActivity.kt`
  - presents login as a full-screen activity with visible page title, URL, and loading state
  - exposes back, forward, home, and reload controls
  - routes the system back button to `WebView.goBack()` before closing the activity
  - enables third-party cookies and DOM storage so OAuth-style login hops can round-trip cleanly

Expected integration flow:

1. Run `./gradlew assembleDebug` or `./gradlew assembleRelease`; Gradle will invoke the matching UniFFI sync task before `preDebugBuild` / `preReleaseBuild`.
2. Keep the files in `src/main/java/com/fire/app/session/` in the same Android module.
3. Create a single `FireSessionStore` instance during app startup and call `restorePersistedSessionIfAvailable()`.
4. Drive the login `WebView` through `FireWebViewLoginCoordinator.completeLogin(webView)`.
5. After login or restore, render the inline topic browser from `MainActivity`.
6. On explicit logout, call `FireWebViewLoginCoordinator.logout()` and clear host-side `CookieManager` entries if desired.

Workspace note:

- The Android host now passes `filesDir/fire` into Rust as the workspace root.
- Rust now initializes shared logging under `filesDir/fire/logs` and keeps xlog cache files under `filesDir/fire/cache/xlog`.
- Rust also mirrors tracing output into `filesDir/fire/diagnostics/fire-readable.log`.
- Rust can resolve relative paths inside that workspace for shared file ownership such as logs, caches, or exports.
- The current persisted session file remains `filesDir/fire/session.json`.

Current browser note:

- The Android shell now loads the real Rust session/topic APIs through generated Kotlin UniFFI bindings.
- Network-backed UniFFI APIs now surface to Kotlin as native `suspend fun` calls instead of a synchronous wrapper.
- The UniFFI boundary now returns all exported host interactions through `FireUniFfiError`; if Rust panics, the boundary logs the panic, returns an `Internal` error, and poisons the current `FireCoreHandle` so the host can recreate it instead of continuing on corrupted state.
- `MainActivity` still renders a compact browser shell, but the data path is no longer stubbed.
- The current browser shell now supports `Load More` pagination, category metadata derived from the shared Rust bootstrap snapshot, and Rust-owned row/status presentation data instead of rebuilding those labels on Android.
- Topic detail now opens in a dedicated activity instead of being embedded under the feed list.
- The host shell now exposes a diagnostics screen for readable logs and Rust-owned request traces.

Note:

- The generated Kotlin bindings are configured by `rust/crates/fire-uniffi/uniffi.toml`, currently use the `uniffi.fire_uniffi` package, and load `libfire_uniffi.so` through JNA.
- Android Rust targets now inherit `-Wl,-z,max-page-size=16384` from `.cargo/config.toml` so packaged shared libraries are aligned for Android 15+ 16 KB page-size compatibility.
- `assembleDebug` now packages Rust debug `.so` outputs and `assembleRelease` packages Rust release `.so` outputs.
- Build with a full JDK that includes `jlink`. On this machine, `ANDROID_HOME=$HOME/Library/Android/sdk ANDROID_SDK_ROOT=$HOME/Library/Android/sdk JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ./gradlew assembleDebug` and `./gradlew assembleRelease` are verified working.
- The Gradle build expects an Android SDK/NDK installation. By default the sync script resolves the NDK from `$ANDROID_NDK_HOME`, `$ANDROID_NDK_ROOT`, or `$ANDROID_HOME/ndk/28.2.13676358`.
- Async UniFFI bindings rely on `kotlinx-coroutines-core`, which is now declared directly by this module.
- Android does not have an iOS-style runtime "internet permission" prompt for ordinary web access. `android.permission.INTERNET` is a normal install-time permission, so there is no separate network-permission preflight to mirror.

Unit test coverage now starts with `src/test/java/com/fire/app/TopicPresentationTest.kt`, and CI runs `./gradlew clean testDebugUnitTest assembleDebug` followed by a separate `./gradlew assembleRelease` invocation. Keeping debug/unit and release in separate Gradle processes still matches the currently verified local path and avoids a flaky combined-variant native-lib packaging failure on this machine, while skipping the second `clean` lets the release pass reuse the already prepared Gradle state instead of rebuilding from an empty workspace.

Planned responsibilities beyond the current wiring:

- `WebView` login and Cloudflare challenge flow
- Cookie extraction and sync into the shared Rust core
- Native navigation, rendering, media integration, and notification handling
- Calling Fire Rust bindings through UniFFI-generated Kotlin APIs
