# Android Native App

This directory contains the Android native host for Fire. The app uses the
traditional Android View system, Navigation Fragment for the main shell,
RecyclerView/Paging for list surfaces, and Kotlin UniFFI bindings generated from
the shared Rust core at build time.

## Current App Shape

- `MainActivity.kt` hosts the `NavHostFragment` and bottom navigation tabs:
  Home, Notifications, and Profile. Tab selection uses Navigation saved-state
  restoration so loaded tab fragments keep their back stack and ViewModel state
  when switching between the three primary tabs. It enables edge-to-edge
  rendering and keeps the existing root inset listener as the single content
  padding authority around system bars.
- `FireApplication.kt` applies Material You dynamic colors when available and
  exposes a themed context for programmatic Fire color resolution; XML-heavy
  branded surfaces keep the Fire palette resources as their fallback identity.
- `PreheatGateFragment` is the startup authority boundary: it restores the
  persisted Rust session, waits for preloaded data, makes a non-destructive
  login-state decision, and routes to Home or Onboarding. During that check it
  reuses the onboarding visual shell, and failures expose a login action without
  clearing the local session cache. `OnboardingFragment` is only the explicit
  login entry, and `LoginWebViewFragment` owns interactive login.
- `HomeFragment` renders the Rust-backed topic feed with feed-kind, category,
  tag filtering, pull refresh, and debounced MessageBus-triggered Paging
  refresh. Topic-scoped latest events are coalesced for rate limiting, but the
  Android host still refreshes the active Paging source rather than merging
  `topic_ids` rows in place. Topic row opens are single-flight until the user
  returns from native topic detail. New Topic opens `TopicComposerSheet`;
  successful creation opens the native topic detail screen. Topic compose supports
  Rust-backed tag suggestions, `@mention` suggestions, image upload insertion, selection-aware
  Markdown formatting, shared Rust draft restore/autosave/delete, and local
  Markdown preview with upload-image preview. Reply compose also accepts quote
  prefill from topic detail while preserving restored drafts. Empty initial
  Paging loads render shimmered topic-row skeletons in the list area instead of
  a separate blocking spinner.
- `SearchFragment` is a Navigation destination reachable from Home. It calls
  Rust search APIs for all/topic/post/user scopes, renders labeled result
  sections, loads additional full-page results while scrolling, and routes
  results to topic detail or profile.
- `NotificationsFragment` renders paginated notifications, supports single/all
  mark-read, refreshes the bottom-tab unread badge, and routes notifications to
  topic detail or profile.
- `FireFirebaseMessagingService` receives Firebase Cloud Messaging payloads
  when `google-services.json` is supplied locally or by CI. Android owns the
  local notification channel/display and tap routing to native topic/profile
  destinations, while Rust remains the authority for notification state refresh.
  FCM token backend registration is intentionally pending a shared Rust/core
  registration API instead of being implemented as a platform-only backend
  client.
- `ProfileFragment` renders current or public profiles, summary stats, badges,
  profile bio through the shared rich-text renderer, follow/unfollow, and top
  topic navigation. Public profiles expose a private-message composer when the
  backend permits it; the current-user profile exposes Bookmarks, Drafts, Read
  History, Messages, LDC Credit, and CDK connection entry points.
- `LDCFragment` and `CDKFragment` share a fixed ViewBinding screen backed by
  `LdcCdkViewModel`. They display Rust-owned user-info records, run the
  authorization URL -> approval link -> approve redirect -> callback sequence
  through `FireSessionStore`, and expose logout without owning cookies or
  WebView/browser session state.
- `BookmarksFragment` renders the current user's Rust-backed bookmark topic
  list and opens topics at `bookmarkedPostNumber` when the backend provides a
  floor anchor.
- `PrivateMessagesFragment` renders Rust-backed private-message topic lists with
  inbox/sent switching plus a New Message action. Public-profile compose
  pre-fills the target user; mailbox compose accepts searched usernames,
  multiple recipients with token chips, body `@mention` suggestions, image
  upload insertion, selection-aware Markdown formatting, shared Rust draft
  restore/autosave/delete, and local Markdown preview with upload-image preview.
- `TopicDetailActivity` is still the authoritative Android topic detail surface.
  It is intentionally a dedicated activity outside the main tab `NavHost`.
- `core/ui/FireToast.kt` is the shared Material Snackbar wrapper for transient
  success/error/info/warning feedback. Composer sheets and topic-detail action
  flows use it at the UI boundary; ViewModels continue to expose business state
  and never own Android views.

## Topic Detail

`TopicDetailActivity` now loads Rust-owned `TopicDetailPageState` from the
combined topic-detail page path, where the source snapshot carries the full
posts and the slim tree presentation carries only post id / number plus
hierarchy metadata plus the optional first-unread-root suggestion. It renders a
`ConcatAdapter` made of the topic header, original post, reply rows, and a
loading footer. Load-more is driven only by the Rust source cursor over raw
`post_stream.stream`, not by host-managed row windows.

Topic detail preserves Rust tree row order and indentation for Fire's
reply-shaped reading experience, but defaults secondary and deeper replies to a
root-row “查看更多 N 条回复” shortcut so deeply nested threads do not overwhelm
the main reading flow. Explicit target post numbers keep their visible ancestry
while scrolling to the target. Android keeps this on the same RecyclerView,
`ConcatAdapter`, and `PostListAdapter` path, without a parallel source or
host-owned display data model.

When Rust returns `firstUnreadRootPostNumber`, Android consumes it only for the
initial topic-detail load with no explicit notification/search/bookmark/share
target. Android only enables the Rust unread-root suggestion query for that
first-open path. Explicit target post numbers keep priority, and refresh or
MessageBus updates never trigger unread-root scrolling or unread-root auto-batch
requests.

Post rows consume Rust-owned `TopicPostAuthorMetadata` for display name,
username, title, group/flair name, staff markers, and status text. Android only
renders this metadata in the native RecyclerView row; it does not reconstruct
author badges from profile fetches or parsed cooked HTML.

Post row avatars and usernames route directly to the native user-info sheet when
the row has a non-empty username. Author metadata is split into compact colored
badges on the username line (`Lv.N`, staff/group/flair) and a shorter secondary
line (`@username`, title/status), with the timestamp trailing the first line and
`#N楼` trailing the second line.

Topic-detail rich text consumes Rust `RenderDocument` blocks plus
`imageAttachments`. Android keeps inline image ordering from render blocks,
uses Rust attachment URLs for linked/original image selection, normalizes
relative LinuxDo image URLs before Coil load/preview, and appends attachment
images that were not represented by render-tree image blocks instead of parsing
`post.cooked`.

Current topic-detail interactions:

- topic-level reply FAB through `ReplyComposerSheet`, with `@mention`
  suggestions, image upload insertion, selection-aware Markdown formatting,
  shared Rust draft restore/autosave/delete, and local Markdown preview with
  upload-image preview
- per-post reply from the post row
- per-post quote reply from the post row, using Rust-provided
  `RenderDocumentState.plainText` for the quoted body instead of parsing cooked
  HTML on Android
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
- notification, search, profile, user-sheet, and topic-detail avatars all use
  the shared `FireImageLoader` Coil pipeline with memory and disk caching.
  `FireAvatarUrls` resolves common avatar surfaces to a canonical 384px
  request URL so detail rows, notifications, search results, profiles, and
  compact user sheets reuse the same cache entry instead of downloading the
  same avatar at per-surface `{size}` URLs.
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
- original-post body, poll, Boost, and action surfaces use the same content
  width as the topic title instead of inheriting the reply avatar-column inset
- Boost short replies render as body-only content from Rust-owned
  `TopicPostBoostState.displayText` and `renderDocument`, stripping leading
  `@username:` attribution instead of showing or re-adding the Boost author
  prefix. They use a body overlay/barrage for original posts with visible body
  text, and a compact one-or-two-row manual horizontal chip scroller for
  replies or posts without a body text target, without Android-side Boost HTML
  parsing; manual chips fill the first row left-to-right, expand to the second
  row only when needed, then continue as the next two-row horizontal page under
  user swipes. Overlay mode caps visible boosts to five display lines, uses at
  most five lanes, plays each post/Boost batch once before hiding, and
  pauses/resumes animation timing around active RecyclerView scrolling to avoid
  overlap and broad body-text occlusion, while reply/comment Boost chips move
  only through user swipes
- searchable full reaction picker from Rust-provided enabled reactions, with
  reaction-user lookup from both the rendered summary and picker rows
- toolbar bell notification-level selection for non-private-message topics
- bookmark reminder date/time picker with host-owned local notifications after
  successful Rust bookmark mutations
- in-topic search over already loaded Rust `RenderDocumentState.plainText`, with
  active-result highlight and previous/next floor navigation
- FCM push payloads are parsed in the Android host for local display only:
  topic ids, post numbers, profile usernames, and LinuxDo/fire deep links route
  to existing native surfaces, then Rust notification state is refreshed through
  the existing session store path when possible
- reply-context lookup from the rendered reply target, showing source and
  direct replies
- post delete/recover actions when the backend exposes those permissions
- post report flow using Rust-provided post action types with moderator-message
  prompts when required
- target post scrolling for notification/search deep links, with Rust's
  first-unread-root suggestion used only when no explicit target was supplied
- topic/reaction/poll MessageBus subscriptions with debounced detail refresh
- MessageBus-driven detail refresh now waits until RecyclerView scrolling returns
  to idle before applying the latest refreshed source snapshot + tree presentation,
  so live updates do not rebind the visible post list mid-scroll
- identical refreshed detail / row payloads are now dropped before they hit the
  observable UI state, avoiding redundant header and post-list submissions
- initial-load topic-detail failures render as a solid top error banner with
  retry, while refresh, load-more, and MessageBus failures remain transient
  toast errors so stale page-level errors do not float over later topics

Current iOS/Rust expose topic voter lookup and poll counts/votes, but not a
poll-option voter-list API or iOS poll-voter sheet; Android follows that same
capability boundary.

## Login Boundaries

Android now keeps request-failure handling single-path:

- First `FireSessionStore` / `FireAppCore` creation goes through the suspend
  `FireSessionStoreRepository.get(context)` IO path before returning to UI
  work, including startup preheat and other Fragment/Activity entry points.
  Startup preheat logs timing fields for session-store get/create,
  startup-session preparation, preloaded-data wait, and the non-destructive
  login-state decision.
- `LoginRequired` no longer auto-opens login UI and no longer triggers local
  logout side effects during ordinary request handling; navigation back to
  onboarding still depends on the authoritative Rust session snapshot.
- `CloudflareChallenge` requests now go through a registered host-owned
  challenge Activity, including background/silent operations that hit CF while
  the app can launch the Activity. The Activity records and clears the old
  `cf_clearance`, waits for a fresh value, and returns that accepted value plus
  relevant browser cookies to Rust so Rust can retry the original request once.
  The deleted baseline clearance is restored if verification is cancelled. The
  challenge Activity owns its edge-to-edge system bar insets so the title and
  close action remain outside the status-bar touch area.
- Challenge completion is checked from page/navigation callbacks,
  `/cdn-cgi/challenge-platform/` resource signals, injected fetch/XHR and
  pagehide/beforeunload signals, plus a 1-second cookie polling fallback.
- Rust still supplies request presentation context for diagnostics and future
  host-specific UI choices, but the Android bridge no longer rejects a challenge
  solely because the triggering request was marked background.
- Topic detail publishes loaded header counters back to the visible home list
  through a stateful `HomeTopicDetailPatchRepository`, letting already-loaded rows update
  `postsCount`, `replyCount`, `views`, `lastReadPostNumber`, and
  `highestPostNumber` immediately even if Home was stopped while detail was
  visible. The patch also recomputes unread/new state from the patched read
  position while the next Paging load remains the authoritative Rust-backed
  refresh.
- Home, topic detail, notifications, search, bookmarks, private messages, and
  composer flows all surface those failures through the same error-display path
  used for any other request failure.
- The remaining interactive browser surfaces are the explicit login WebView and
  the dedicated Cloudflare challenge Activity; both still use
  `FireWebViewSupport` and remain platform-owned.
- Android WebView cookie extraction uses `CookieManagerCompat.getCookieInfo()`
  for domain/path/flag metadata. Low-confidence `CookieManager.getCookie()`
  name/value snapshots are not accepted for login finalization or trusted
  Cloudflare challenge completion.

Do not move explicit login WebView rendering, CookieManager extraction, or
platform browser context ownership into Rust. Rust remains responsible for
session state, cookie normalization, CSRF/bootstrap refresh, API orchestration,
MessageBus, and Cloudflare/login error classification.

## Rust And UniFFI Wiring

- `FireSessionStore.kt` owns `FireAppCore` and passes `filesDir/fire` as the
  shared Rust workspace root.
- `FireSessionStore.kt` also wraps `core.ldc()` for LDC/CDK OAuth user-info,
  authorization, callback, and logout calls. The UI layer keeps only transient
  presentation state while Rust owns API orchestration.
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
