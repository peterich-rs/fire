# Android Native App

This directory contains the Android native host for Fire. The app uses the
traditional Android View system, Navigation Fragment for the main shell,
RecyclerView/Paging for list surfaces, and Kotlin UniFFI bindings generated from
the shared Rust core at build time.

## Current App Shape

- `MainActivity.kt` hosts the `NavHostFragment` and bottom navigation tabs:
  Home, Notifications, and Profile. Tab selection uses Navigation saved-state
  restoration so loaded tab fragments keep their back stack and ViewModel state
  when switching between the three primary tabs.
- `OnboardingFragment` restores the persisted Rust session and routes logged-in
  users into Home. `LoginWebViewFragment` owns interactive login.
- `HomeFragment` renders the Rust-backed topic feed with feed-kind, category,
  tag filtering, pull refresh, MessageBus refresh, and visible Search/New Topic
  actions. New Topic opens `TopicComposerSheet`; successful creation opens the
  native topic detail screen. Topic compose supports Rust-backed tag
  suggestions, `@mention` suggestions, image upload insertion, and shared Rust
  draft restore/autosave/delete, and local Markdown preview with upload-image
  preview.
- `SearchFragment` is a Navigation destination reachable from Home. It calls
  Rust search APIs for all/topic/post/user scopes, renders labeled result
  sections, loads additional full-page results while scrolling, and routes
  results to topic detail or profile.
- `NotificationsFragment` renders paginated notifications, supports single/all
  mark-read, refreshes the bottom-tab unread badge, and routes notifications to
  topic detail or profile.
- `ProfileFragment` renders current or public profiles, summary stats, badges,
  profile bio through the shared rich-text renderer, follow/unfollow, and top
  topic navigation. Public profiles expose a private-message composer when the
  backend permits it; the current-user profile exposes Bookmarks and Messages
  entry points.
- `BookmarksFragment` renders the current user's Rust-backed bookmark topic
  list and opens topics at `bookmarkedPostNumber` when the backend provides a
  floor anchor.
- `PrivateMessagesFragment` renders Rust-backed private-message topic lists with
  inbox/sent switching plus a New Message action. Public-profile compose
  pre-fills the target user; mailbox compose accepts searched usernames,
  multiple recipients with token chips, body `@mention` suggestions, image
  upload insertion, shared Rust draft restore/autosave/delete, and local
  Markdown preview with upload-image preview.
- `TopicDetailActivity` is still the authoritative Android topic detail surface.
  It is intentionally a dedicated activity outside the main tab `NavHost`.

## Topic Detail

`TopicDetailActivity` loads `fetchTopicScreen` from Rust and renders a
`ConcatAdapter` made of the topic header, original post, response rows, and a
loading footer. Replies are paged through Rust response cursors.

Current topic-detail interactions:

- topic-level reply FAB through `ReplyComposerSheet`, with `@mention`
  suggestions, image upload insertion, shared Rust draft restore/autosave/delete,
  and local Markdown preview with upload-image preview
- per-post reply from the post row
- per-post heart like/unlike through shared Rust interaction APIs
- per-post custom reaction selection from Rust bootstrap-enabled reactions
- topic and per-post bookmark create/update/delete through shared Rust
  notification bookmark APIs
- topic edit and post edit through shared Rust mutation APIs
- author/profile navigation through the app `fire://profile/{username}` route
- cooked image attachment rendering with a full-screen native viewer
- AI summary loading in the topic header when Rust reports summary availability,
  including retry and metadata display
- topic vote / remove-vote plus topic voter lookup when the backend exposes
  topic voting
- post poll display and regular/multiple poll vote submission/removal
- reaction-user lookup from the rendered post reaction summary
- topic notification-level selection for non-private-message topics
- reply-context lookup from the rendered reply target, showing source and
  direct replies
- post delete/recover actions when the backend exposes those permissions
- post report flow using Rust-provided post action types with moderator-message
  prompts when required
- target post scrolling for notification/search deep links
- topic/reaction/poll MessageBus subscriptions with debounced detail refresh

Current iOS/Rust expose topic voter lookup and poll counts/votes, but not a
poll-option voter-list API or iOS poll-voter sheet; Android follows that same
capability boundary.

## Cloudflare And Login Boundaries

Android keeps Cloudflare recovery host-owned:

- General Cloudflare challenges open `CloudflareChallengeActivity`, which loads
  `https://linux.do/` in a full-screen WebView.
- Topic-detail challenges stay inside `TopicDetailActivity` and show an inline
  WebView under the toolbar, loading `https://linux.do/t/{topicId}`.
- Login and general challenge WebViews share the browser-like
  `FireWebViewSupport` profile through `CloudflareChallengeSupport.configureWebView`:
  persistent cookies, third-party cookies, JavaScript, DOM storage, database
  storage, AndroidX WebKit Safe Browsing, browser-compatible User-Agent
  normalization, and same-context handling for `window.open` / popup login
  flows. Non-Web schemes, file/content access, and mixed content remain blocked.
- `CloudflareWebViewCookieSyncer` syncs browser context only after
  `cf_clearance` is visible, then calls
  `FireWebViewLoginCoordinator.syncBrowserContext`.

Do not move WebView challenge completion, CookieManager extraction, or
platform browser context ownership into Rust. Rust remains responsible for
session state, cookie normalization, CSRF/bootstrap refresh, API orchestration,
MessageBus, and Cloudflare error classification.

## Rust And UniFFI Wiring

- `FireSessionStore.kt` owns `FireAppCore` and passes `filesDir/fire` as the
  shared Rust workspace root.
- The persisted session snapshot lives at `filesDir/fire/session.json`.
- Shared logs and diagnostics are rooted under `filesDir/fire/logs` and
  `filesDir/fire/diagnostics`.
- Android UI root coroutines use the shared `core/error/FireErrorHandling.kt`
  boundary for Rust/UniFFI failures. It rethrows coroutine cancellation, classifies
  `FireUniFfiException`, emits user-safe messages or Cloudflare recovery events,
  and records the operation, error id, kind, details, and stack in both Logcat and
  Rust diagnostics host logs.
- Cold session restore keeps the locally restored Rust session if an opportunistic
  bootstrap refresh fails. A refused or offline `GET /` is therefore traceable in
  diagnostics but does not crash the main thread or discard the usable local
  session.
- `scripts/sync_uniffi_bindings.sh` generates Kotlin bindings and packages
  `libfire_uniffi.so` for debug/release variants before Android builds.
- Generated Kotlin bindings are split by namespace under
  `uniffi.fire_uniffi*` and load the single shared `libfire_uniffi.so` through
  JNA.

## Build And Verification

Use JDK 17 and a local Android SDK/NDK:

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
export ANDROID_HOME=/Users/zhangfan/Library/Android/sdk
export ANDROID_SDK_ROOT=/Users/zhangfan/Library/Android/sdk
./gradlew compileDebugKotlin
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

CI runs debug unit tests and debug/release assembly. Android Rust targets inherit
the workspace linker settings for Android 15+ 16 KB page-size compatibility.
