# Android Native App

This directory now contains a runnable Android host shell. The current build
generates Kotlin UniFFI bindings at build time and packages Rust-backed Android
shared libraries for the app to load through JNA.

Current host-side app wiring lives under `src/main/java/com/fire/app/` plus `src/main/java/com/fire/app/session/`:

- `FireSessionStore.kt`
  - owns `FireAppCore`
  - passes the platform workspace root (`filesDir/fire`) into Rust during initialization
  - restores persisted session snapshots on cold start
  - persists the latest Rust session snapshot to `filesDir/fire/session.json`
  - lets Rust initialize shared logs under `filesDir/fire/logs`
  - wraps `syncLoginContext`, `refreshBootstrap`, `refreshCsrfToken`, diagnostics reads, topic/user/search/notification/bookmark/history fetches including topic AI summaries and reaction-user lists, topic/reply/private-message/bookmark creation, topic/post update, topic notification-level updates, bookmark update/delete, post like/unlike/custom-reaction/poll-vote/topic-vote/delete/recover/report actions, topic voter fetches, notification mark-read, follow/unfollow, and logout
- `scripts/sync_uniffi_bindings.sh`
  - builds an unstripped host debug library for UniFFI metadata extraction
  - reads generator settings from `rust/crates/fire-uniffi/uniffi.toml`
  - generates Kotlin bindings from `fire-uniffi`
  - cross-compiles `libfire_uniffi.so` for `arm64-v8a` and `x86_64`
  - resolves the host-side UniFFI metadata library extension per OS so Gradle sync can run on macOS and Linux CI
  - keeps release Android `.so` packaging separate from host bindgen input so Linux CI is not broken by the workspace `strip = true` release profile
  - writes variant-specific generated sources and JNI libraries into the Gradle build directory (Kotlin bindings land under `build/generated/source/uniffi/<buildType>/kotlin/`, mirroring the AGP convention for generated sources such as `build/generated/source/buildConfig`)
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
  - renders a paginated topic browser with feed filters, private-message inbox/sent filters, bookmarks, read history, category-aware Rust-owned topic rows, and a focused selected-topic summary
  - opens a native new-topic composer from the feed shell, validates the shared title/body/category/tag constraints, submits through shared Rust `createTopic`, then opens the created topic detail
  - exposes a category notification picker from the feed shell, using bootstrap `site.categories[].notificationLevel` for the current value and shared Rust `setCategoryNotificationLevel` for Muted / Regular / Tracking / Watching / Watching First Post updates
  - opens topic detail in a dedicated screen instead of fetching and rendering it inline in the feed host
- `DiagnosticsActivity.kt`, `LogViewerActivity.kt`, `RequestTraceDetailActivity.kt`
  - surface a native diagnostics entry point
  - list readable/shared log files from the Rust workspace
  - render a reverse-chronological request trace overview and per-request execution-chain/detail pages
- `NotificationsActivity.kt`
  - opens a native notification center from the host shell
  - renders Rust-backed unread/high-priority counters plus a paginated full notification list
  - marks single notifications or the full list read through shared Rust APIs
  - opens native topic detail at the notification post number when `topicId` is present, otherwise falls back to the actor profile when a username is available
- `SearchActivity.kt`
  - opens a native LinuxDo search surface from the host shell
  - calls the shared Rust `search` API with All / Topics / Posts / Users filters
  - renders topic, post, and user result groups with load-more paging when the backend reports more results
  - opens topic results in native topic detail, post results at their floor, and user results in native profile
- `TopicDetailActivity.kt`
  - loads topic detail on demand from the shared Rust API
  - renders topic detail as `header + body + response`: the original post stays independent, while replies come from Rust-owned tree rows paged by top-level reply branch
  - loads optional Rust-backed topic AI summaries before the post list when the detail payload advertises `summarizable`, `hasCachedSummary`, or `hasSummary`; empty summaries remove the placeholder and failures stay scoped to a retryable summary card
  - opens public profiles from post author names and reply-context rows
  - opens native reply-context dialogs that prioritize Rust-backed recursive reply IDs, batch those IDs through `fetchTopicPosts`, and fall back to `fetchPostReplies` only when the reply-ID tree is empty
  - opens a native reply composer for topic-level replies and per-post floor replies, validates the shared `minPostLength`, and posts through shared Rust `createReply`
  - exposes a top-level topic editor when `details.canEdit` is true, validates title/category/tag constraints from bootstrap, and saves through shared Rust `updateTopic`
  - exposes a post editor from each editable post's Actions menu, preloads `raw` when available, accepts an optional edit reason, and saves through shared Rust `updatePost`
  - renders native poll cards from `post.polls`, supports single-option direct voting, multiple-choice picker submission, and vote removal through shared Rust poll APIs
  - renders the topic voting-plugin panel when available, supports vote/unvote through shared Rust topic voting APIs, and opens a voters dialog backed by the shared voter list API
  - exposes a topic-level bookmark button plus per-post bookmark actions, backed by shared Rust notification bookmark write APIs; the editor supports bookmark name/reminder updates and deletion when an existing bookmark id is present
  - exposes a public-topic notification-level picker for Muted / Regular / Tracking / Watching, backed by shared Rust `/t/{topicId}/notifications`; private-message threads hide this topic-only control
  - exposes a per-post heart like/unlike button plus a custom reaction picker backed by shared Rust `likePost` / `unlikePost` / `togglePostReaction`, then refreshes the target floor to sync reaction state
  - opens a native reaction-user dialog from each post's reaction summary, backed by shared Rust `fetchReactionUsers(postId)`, and lets user rows open native profiles
  - exposes per-post actions for delete, recover, and report through shared Rust post-management APIs, including server-provided report types and required-message handling
- `ProfileActivity.kt`
  - opens a native public profile screen from topic detail authors
  - loads profile, summary, followers, following, user reactions, follow/unfollow, and user notification-level updates through the shared Rust user APIs
  - exposes Normal / Mute / Ignore user notification controls when the profile payload permits mute/ignore, including an ignore-duration picker before calling the shared write API
  - opens a single-recipient private-message composer when the profile allows messaging, validates the shared private-message minimum lengths, and sends through shared Rust `createPrivateMessage`
  - renders profile bio through the shared cooked-HTML AST renderer and opens top topics/replies/reaction rows in native topic detail
- `FireCookedHtmlRenderer.kt`
  - renders topic-detail cooked post bodies from the shared Rust `parseCookedHtml` AST instead of reparsing raw HTML in Kotlin
  - currently covers native paragraph, heading, quote, list, code block, details/spoiler, table text fallback, link/mention/hashtag spans, and image/onebox/iframe/attachment fallback cards; compact reply-context rows still use the shared plain-text helper for previews
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
- Debug builds may also mirror that shared pipeline into Logcat, while release builds keep the shared logs in Xlog/readable-log files only.
- Rust can resolve relative paths inside that workspace for shared file ownership such as logs, caches, or exports.
- The current persisted session file remains `filesDir/fire/session.json`.

Current browser note:

- The Android shell now loads the real Rust session/topic APIs through generated Kotlin UniFFI bindings.
- Network-backed UniFFI APIs now surface to Kotlin as native `suspend fun` calls instead of a synchronous wrapper.
- The UniFFI boundary now returns all exported host interactions through `FireUniFfiError`; if Rust panics, the boundary logs the panic, returns an `Internal` error, and poisons the current `FireAppCore` so the host can recreate it instead of continuing on corrupted state.
- `MainActivity` still renders a compact browser shell, but the data path is no longer stubbed.
- The current browser shell now supports `Load More` pagination, category metadata derived from the shared Rust bootstrap snapshot, and Rust-owned row/status presentation data instead of rebuilding those labels on Android.
- The browser filter bar now exposes Rust-backed private-message inbox and sent-message lists; rows show Discourse participants when the response provides them and open the same native topic detail screen as normal topic lists.
- The browser filter bar now also exposes Rust-backed bookmarks and read history. Bookmark rows show bookmark post/name/reminder metadata and open topic detail at `bookmarkedPostNumber` when available; read-history rows open at `lastReadPostNumber`.
- The main browser shell now exposes category notification-level updates through shared Rust notification bindings and refreshes bootstrap after each accepted change so category `notificationLevel` returns to the server-owned value.
- The host shell now opens a Rust-backed native notification center with paginated notifications, unread/high-priority counters, single/all mark-read actions, and topic/profile navigation.
- The host shell now opens a Rust-backed native search screen with result-type filters, paginated result loading, and native navigation from search results into topics, posts, and profiles.
- Topic detail now opens in a dedicated activity instead of being embedded under the feed list.
- Generated Kotlin topic bindings expose `createTopic(TopicCreateRequestState)` from the shared Rust creation path; Android main now uses it for a native new-topic composer with bootstrap-driven minimum title/body length, default category, category permission, required-tag, and allowed-tag validation.
- Generated Kotlin topic bindings expose `fetchTopicAiSummary(topicId, skipAgeCheck)` from the shared Rust Discourse AI summary path; Android topic detail renders the returned `TopicAiSummaryState` as a native summary card without blocking the main detail body.
- Generated Kotlin topic bindings expose `createPrivateMessage(PrivateMessageCreateRequestState)` from the shared Rust creation path; Android public profiles now use it for single-recipient private messages, validate `minPersonalMessageTitleLength` / `minPersonalMessagePostLength`, and open the created private-message thread.
- Generated Kotlin topic bindings expose `createReply(TopicReplyRequestState)` from the shared Rust creation path; Android topic detail now uses it for topic replies and floor replies, then reloads and scrolls to the created post.
- Generated Kotlin topic bindings now also expose `fetchTopicScreen(TopicScreenQueryState)` and `fetchTopicResponsePage(TopicResponsePageQueryState)`; Android topic detail uses them to render `header/body/response`, keep the original post separate from replies, and paginate reply trees by top-level branch instead of flattening the whole topic stream on the host.
- Generated Kotlin topic bindings expose `updateTopic(TopicUpdateRequestState)` and `updatePost(PostUpdateRequestState)`; Android topic detail now uses them for editable topic metadata and editable post bodies, then reloads the affected detail state.
- Generated Kotlin topic bindings expose `votePoll(postId, pollName, options)` and `unvotePoll(postId, pollName)`; Android topic detail now renders native poll cards from each post and reloads the affected floor after voting changes.
- Generated Kotlin topic bindings expose `voteTopic(topicId)`, `unvoteTopic(topicId)`, and `fetchTopicVoters(topicId)`; Android topic detail now renders the topic voting-plugin panel, reloads topic detail after vote changes, and opens native voter-list dialogs.
- Generated Kotlin notification bindings expose `createBookmark`, `updateBookmark`, and `deleteBookmark`; Android topic detail now uses them from the topic bookmark button and each post's Actions menu, then reloads the topic to sync bookmark state.
- Generated Kotlin notification bindings expose `setTopicNotificationLevel(topicId, notificationLevel)` and `setCategoryNotificationLevel(categoryId, notificationLevel)`; Android topic detail uses the topic endpoint for public topics, while Android main uses the category endpoint for bootstrap-backed category notification changes.
- Generated Kotlin topic bindings now include shared Rust post delete/recover/flag APIs plus `fetchPostActionTypes()` for server-provided flag metadata; Android topic detail uses them from a per-post Actions menu and refreshes the affected floor after each accepted operation.
- Generated Kotlin topic bindings also expose `TopicPostState.replyToUser`, `fetchPostReplyIds(postId)`, `fetchPostReplies(postId, after)`, and `fetchPostReplyHistory(postId)` from the shared Rust reply-context implementation; Android topic detail now renders reply-to labels with `replyToUser` when available, lets those labels jump to the target floor, and opens a native reply-context dialog for recursive direct replies / reply-history source posts.
- Generated Kotlin topic bindings expose `likePost(postId)`, `unlikePost(postId)`, `togglePostReaction(postId, reactionId)`, and `fetchReactionUsers(postId)` from the shared Rust reaction implementation; Android topic detail now uses heart like/unlike as the fast path, builds a custom reaction picker from `bootstrap.enabledReactionIds` plus the post's existing reactions, reloads the affected post floor after each update, and opens native reaction-user dialogs from post reaction summaries.
- Generated Kotlin user bindings now back an Android public profile surface: topic-detail author names open `ProfileActivity`, which renders profile metadata, summary stats, top topics/replies, badges, a paginated user reactions list, followers/following dialogs, Rust-backed follow/unfollow actions, user Normal / Mute / Ignore notification-level updates, and single-recipient private-message creation when the server allows it.
- The host shell now exposes a diagnostics screen for readable logs and Rust-owned request traces.

Note:

- The generated Kotlin bindings are configured by `rust/crates/fire-uniffi/uniffi.toml`, split across `uniffi.fire_uniffi`, `uniffi.fire_uniffi_diagnostics`, `uniffi.fire_uniffi_messagebus`, `uniffi.fire_uniffi_notifications`, `uniffi.fire_uniffi_search`, `uniffi.fire_uniffi_session`, `uniffi.fire_uniffi_topics`, `uniffi.fire_uniffi_types`, and `uniffi.fire_uniffi_user` (one per namespace), and load `libfire_uniffi.so` through JNA (single cdylib shared across every namespace).
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
