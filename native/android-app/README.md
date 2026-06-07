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
- `PreheatGateFragment` is the startup authority boundary: it restores the
  persisted Rust session, waits for preloaded data, runs Rust's login-state
  probe, and routes to Home or Onboarding. During that check it reuses the
  onboarding visual shell, keeps the login action hidden, and leaves failures on
  the same screen with a retry action. `OnboardingFragment` is only the explicit
  login entry, and `LoginWebViewFragment` owns interactive login.
- `HomeFragment` renders the Rust-backed topic feed with feed-kind, category,
  tag filtering, pull refresh, MessageBus refresh, and visible Search/New Topic
  actions. New Topic opens `TopicComposerSheet`; successful creation opens the
  native topic detail screen. Topic compose supports Rust-backed tag
  suggestions, `@mention` suggestions, image upload insertion, and shared Rust
  draft restore/autosave/delete, and local Markdown preview with upload-image
  preview. Empty initial Paging loads render topic-row skeletons in the list area
  instead of a separate blocking spinner.
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

`TopicDetailActivity` now loads Rust-owned `TopicDetailPageState` from the
combined topic-detail page path, where the source snapshot carries the full
posts and the slim tree presentation carries only post id / number plus
hierarchy metadata. It renders a `ConcatAdapter` made of the topic header,
original post, reply rows, and a loading footer. Load-more is driven only by the
Rust source cursor over raw `post_stream.stream`, not by host-managed row
windows.

Current topic-detail interactions:

- topic-level reply FAB through `ReplyComposerSheet`, with `@mention`
  suggestions, image upload insertion, shared Rust draft restore/autosave/delete,
  and local Markdown preview with upload-image preview
- per-post reply from the post row
- per-post heart like/unlike through shared Rust interaction APIs
- per-post custom reaction selection from Rust bootstrap-enabled reactions
- topic and per-post bookmark create/update/delete through shared Rust
  notification bookmark APIs
- topic edit and post edit through shared Rust mutation APIs; post edit requires
  server-provided raw text and does not derive editable text from `cooked`
- author/profile taps, mentions, and profile links open the compact user sheet,
  with a private-message entry when the backend allows it
- rich text and image blocks rendered inline from Rust `RenderDocument` order,
  without Android-side `post.cooked` parsing or render-document fallback, with
  compact loading/error placeholders, manual retry, and a full-screen ZoomImage
  + Coil preview that supports pinch/pan gestures and reuses the shared image
  cache for the same URL
- Rust filters attachment metadata text whose prefix may be a filename/hash but
  whose suffix is dimensions plus file size, and quote chrome/avatar content
  before Android maps blocks to `Spannable` / image views
- quote previews render as shared two-line compact blocks, and onebox previews
  display Rust-derived title/description without Android-side link-preview
  fetching or HTML parsing
- ordinary web links open the host-owned in-app WebView, while LinuxDo topic
  links route to native topic detail
- AI summary loading in the topic header when Rust reports summary availability,
  including retry and metadata display
- topic vote / remove-vote plus topic voter lookup when the backend exposes
  topic voting
- post poll display and regular/multiple poll vote submission/removal
- poll option titles from Rust-provided plain text, without HTML parsing in the
  row binding path
- reaction-user lookup from the rendered post reaction summary
- topic notification-level selection for non-private-message topics
- reply-context lookup from the rendered reply target, showing source and
  direct replies
- post delete/recover actions when the backend exposes those permissions
- post report flow using Rust-provided post action types with moderator-message
  prompts when required
- target post scrolling for notification/search deep links
- topic/reaction/poll MessageBus subscriptions with debounced detail refresh
- MessageBus-driven detail refresh now waits until RecyclerView scrolling returns
  to idle before applying the latest refreshed source snapshot + tree presentation,
  so live updates do not rebind the visible post list mid-scroll
- identical refreshed detail / row payloads are now dropped before they hit the
  observable UI state, avoiding redundant header and post-list submissions

Current iOS/Rust expose topic voter lookup and poll counts/votes, but not a
poll-option voter-list API or iOS poll-voter sheet; Android follows that same
capability boundary.

## Login Boundaries

Android now keeps request-failure handling single-path:

- First `FireSessionStore` / `FireAppCore` creation goes through the suspend
  `FireSessionStoreRepository.get(context)` IO path before returning to UI
  work, including startup preheat and other Fragment/Activity entry points.
  Startup preheat logs timing fields for session-store get/create,
  startup-session preparation, preloaded-data wait, and the login probe.
- `LoginRequired` no longer auto-opens login UI and no longer triggers local
  logout side effects during ordinary request handling; navigation back to
  onboarding still depends on the authoritative Rust session snapshot.
- Foreground-capable `CloudflareChallenge` requests now go through a registered
  host-owned challenge Activity, which waits for a new `cf_clearance` and then
  returns the relevant browser cookies to Rust so Rust can retry the original
  request once.
- Background or silent `CloudflareChallenge` work does not steal focus; the
  platform returns an incomplete challenge result and Rust surfaces the error.
- Home, topic detail, notifications, search, bookmarks, private messages, and
  composer flows all surface those failures through the same error-display path
  used for any other request failure.
- The remaining interactive browser surfaces are the explicit login WebView and
  the dedicated Cloudflare challenge Activity; both still use
  `FireWebViewSupport` and remain platform-owned.

Do not move explicit login WebView rendering, CookieManager extraction, or
platform browser context ownership into Rust. Rust remains responsible for
session state, cookie normalization, CSRF/bootstrap refresh, API orchestration,
MessageBus, and Cloudflare/login error classification.

## Rust And UniFFI Wiring

- `FireSessionStore.kt` owns `FireAppCore` and passes `filesDir/fire` as the
  shared Rust workspace root.
- The persisted session snapshot lives at `filesDir/fire/session.json`.
- Shared logs and diagnostics are rooted under `filesDir/fire/logs` and
  `filesDir/fire/diagnostics`.
- Android UI root coroutines use the shared `core/error/FireErrorHandling.kt`
  boundary for Rust/UniFFI failures. It rethrows coroutine cancellation, classifies
  `FireUniFfiException`, emits user-safe request-failure messages, and records
  the operation, error id, kind, details, and stack in both Logcat and
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
