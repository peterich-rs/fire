# Fire Native Workspace

This repository is the Fire native rebuild workspace.

## Roles

- `references/fluxdo/`
  - keeps the legacy Flutter implementation as a read-only behavior reference
  - remains useful for runtime comparison, but no longer defines the new project structure
- `references/dexo/`
  - keeps the native iOS LinuxDo implementation as a read-only behavior reference
  - is useful for comparing WebView login, Cloudflare challenge handling, cookie/user-agent capture, and native cooked-HTML rendering behavior
- `docs/backend-api*.md`
  - hold the backend protocol notes required for the native rebuild
- `third_party/`
  - stores reusable Rust infrastructure repositories
- `rust/`
  - contains the shared Rust core and the UniFFI boundary
- `native/`
  - contains the iOS and Android native host apps

## Local Layout

```text
fire/
  docs/
    backend-api.md
    backend-api/
    architecture/
      fire-native-workspace.md
  native/
    ios-app/
    android-app/
  references/
    fluxdo/
    dexo/
  rust/
    crates/
      fire-models/
      fire-core/
      fire-uniffi/
  third_party/
    openwire/
    xlog-rs/
```

## Shared Core Boundaries

- Platform-owned:
  - WebView login
  - Cloudflare challenge completion
  - browser user-agent selection for embedded auth/challenge WebViews
  - cookie extraction from platform stores
  - crash capture and host-owned APM collection
  - native UI, files, media, notifications, keychain/keystore
- Rust-owned:
  - session state
  - captured browser user-agent persistence and export through the session snapshot
  - session persistence revision tracking for snapshot/auth-cookie writes
  - session epoch invalidation for stale network responses and cookies
  - bootstrap parsing results
  - API orchestration
  - MessageBus
  - in-app notification state and unread-counter reconciliation
  - shared models
  - logging integration
  - request tracing integration
  - Cloudflare challenge detection

## Dependency Strategy

- `openwire` is the shared Rust network layer, with one shared `Client` per `FireCore` instance now carrying both regular API traffic and MessageBus transport.
- Fire scopes MessageBus-specific execution differences through per-call overrides on that shared client; transport-level HTTP/2 keep-alive remains a shared client policy.
- Fire attaches OpenWire's built-in `LoggerInterceptor` to the shared client at header level; the interceptor writes into Fire's tracing/Xlog pipeline and redacts cookies, auth headers, and CSRF tokens.
- Android injects a Rustls connector backed by bundled Mozilla `webpki-roots` and does not enable OpenWire's platform verifier feature for Android targets; non-Android Fire targets keep the platform verifier feature unless they override the connector explicitly.
- `mars-xlog` is the shared logging backend.
- `references/fluxdo` is a reference submodule, not a build dependency.
- `third_party/` stores build dependencies as submodules so the superproject can be pushed cleanly to GitHub.
- The root Cargo workspace owns only the local Fire crates.

## Clean Worktree Workflow

- The repository root may temporarily carry owner-only `openwire` experiments; do not assume the root checkout itself is the delivery baseline.
- The delivery baseline is always the latest `main`, after `git fetch origin` and a fast-forward update to `origin/main`.
- Standard feature work should start from a clean secondary worktree under `../fire-worktrees/`, branched from that updated `main`.
- The current mainline baseline must keep `third_party/openwire` and `third_party/xlog-rs` initialized, clean, and pinned to reviewed commits.
- CI and local verification should fail fast when those required submodules are missing local checkout state, have local modifications, or have uncommitted pointer drift in the superproject.
- Before integrating a long-lived feature branch back to main, first sync it with the latest `main`, then validate the final result from a clean `main` worktree.

## Shared Networking Model

- `fire-core` owns one shared `openwire` client per `FireCore` instance.
- Regular API traffic uses the client's default execution policy.
- MessageBus foreground polls and background notification-alert polls use per-call overrides on that same client.
- MessageBus `clientId` remains a Discourse protocol/runtime identity used by subscriptions, presence, and background alert flows; it is not transport ownership.
- Fire’s local MessageBus runtime separately tracks subscription ownership with per-subscriber owner tokens so overlapping native lifecycles can share one polled channel set without tearing each other down.
- Transport-level HTTP/2 keep-alive is a shared client policy, not a per-request toggle.

## Shared Surface

- `fire-models`
  - defines the shared login/session snapshot, notification models, and topic/private-message-facing models
- `fire-core`
  - owns session sync, bootstrap parsing, auth refresh/logout, persistence, diagnostics, one shared `openwire` client for API and MessageBus transport, topic list/detail reads (including category/tag scoped lists and private-message mailboxes), search reads, reply/reaction/topic/private-message write paths, draft APIs, upload APIs, the Rust MessageBus poll/subscription runtime, notification fetch/state/mark-read reconciliation, topic-reply presence, and `/topics/timings` request shaping
  - finalizes network traces in Rust with terminal outcomes (`Succeeded`, `Failed`, or `Cancelled`); hosts should treat timeline events as intermediate diagnostics instead of completion signals
- `fire-uniffi`
  - exports the shared async API surface, search APIs, notification list/state APIs, MessageBus callback interface, and error model to Swift/Kotlin
- `native/ios-app` and `native/android-app`
  - host WebView login, cookie capture, native UI state, the current topic browser/detail shells, native composer/private-message UX, and native notification surfaces over the shared Rust notification APIs
  - Android topic detail now opens a native public profile screen from author names; that screen consumes the shared Rust user APIs for profile, summary, followers/following, and follow/unfollow
  - Android main browser now also exposes shared Rust private-message, bookmark, and read-history list surfaces, reusing native topic detail for navigation and bookmarked/last-read post targeting
  - Android now exposes a native notification center backed by shared Rust notification state/fetch/mark-read APIs, with paginated rows that open topic floors or public profiles
  - Android now exposes a native search screen backed by shared Rust search APIs, with filters and result navigation into topic detail floors or public profiles
  - Android main browser now exposes shared Rust topic creation through a native composer with bootstrap-driven category, tag, and minimum-length validation
  - Android main browser now exposes shared Rust category notification-level updates, using bootstrap category `notification_level` as the current value and refreshing bootstrap after accepted changes
  - Android public profiles now expose shared Rust private-message creation through a single-recipient native composer when the server marks the target user messageable
  - Android public profiles now expose shared Rust user notification-level updates for Normal / Mute / Ignore, using `user.muted` / `user.ignored` and the server permission flags from the profile payload
  - Android public profiles now expose the shared Rust user reactions list, paging with `before_reaction_user_id` and opening reaction rows in native topic detail at the reacted post number
  - Android topic detail now exposes shared Rust reply creation for topic replies and per-post floor replies
  - Android topic detail now exposes shared Rust topic metadata editing and post body editing through native editors gated by backend edit permissions
  - Android topic detail now exposes shared Rust Topic/Post bookmark create/update/delete through the notification bookmark APIs
  - Android topic detail now exposes shared Rust public-topic notification-level updates through the notification APIs, while hiding that topic-only control for `private_message` threads
  - Android topic detail now exposes shared Rust heart like/unlike plus custom reaction picker actions per post, refreshes the affected floor after each reaction update, and opens native reaction-user dialogs from post reaction summaries
  - Android topic detail now exposes shared Rust poll voting and unvoting through native poll cards rendered from each post's poll state
  - Android topic detail now exposes shared Rust topic voting-plugin vote/unvote actions and voter-list dialogs from the native topic header
  - Android topic detail now exposes shared Rust post delete, recover, and report actions from each post's Actions menu, including server-provided report types
  - iOS topic-detail state is retained by per-view owner tokens while a detail screen is active, so background homepage refreshes can no longer evict an on-screen topic detail cache
  - iOS now keeps a host-only prepared topic-detail render cache and coalesces MessageBus ingress before MainActor delivery, while leaving session/runtime ownership with Rust

The intended native integration order is:

1. Open LinuxDo login in `WKWebView` / `WebView`.
2. After login or Cloudflare verification, read the platform cookie store, the current page HTML/meta, and the live WebView/browser user agent. Hosts should use a browser-compatible fallback user agent and a default persistent browser store for embedded auth/challenge WebViews before a live value has been captured. Android login WebViews should enable AndroidX WebKit Safe Browsing, block non-web schemes and local file/content access, and apply system-bar insets to host chrome when the shell is immersive.
3. Call `sync_login_context` in Rust with the full same-site browser cookie batch, optional username, CSRF, the preferred homepage HTML captured through the browser context, and the WebView/browser user agent.
4. Persist the latest session snapshot through the host-appropriate session policy:
  - iOS currently writes the full `session.json` snapshot during the active diagnostics-heavy development phase, keeps the full same-site browser cookie batch in Keychain with expiry metadata, and gates both writes off Rust-owned snapshot/auth-cookie persistence revisions instead of diffing exported session JSON in Swift. Cookie identity follows the shared Rust model: `(name, normalizedDomain, path)`, with a leading `.` stripped from the identity domain.
   - Android currently uses `export_session_json` or `save_session_to_path` until Keystore-backed parity lands.
5. On cold start, restore the snapshot through `restore_session_json` or `load_session_from_path`.
6. Before any authenticated request, hosts that keep browser cookies outside `session.json` must re-inject that platform cookie batch into Rust.
7. If homepage HTML is unavailable or stale, or the restored authenticated snapshot is missing username/preloaded bootstrap fields, call `refresh_bootstrap_if_needed`. When homepage bootstrap still lacks site metadata such as categories/top tags, the shared Rust layer now falls back to `/site.json`. Only treat `shared_session_key` as required when MessageBus uses a cross-origin long-polling host.
8. If the restored session is otherwise ready but the local snapshot still lacks CSRF, call `refresh_csrf_token_if_needed` before surfacing a fully ready authenticated session. iOS no longer performs this repair on cold start or at login handoff: hosts rely on the shared authenticated-write preflight to fetch CSRF lazily, and the Rust write path itself sends `X-CSRF-Token: undefined` as a final fallback so the BAD CSRF retry can refresh and replay just like Discourse's official frontend. Write APIs can reuse `refresh_csrf_token_if_needed` whenever they need a newer token.
9. Use `fetch_topic_list` (global, category-scoped, tag-scoped, or private-message mailbox variants via `TopicListQuery`), `fetch_topic_detail`, and `fetch_topic_ai_summary` for the authenticated topic read paths. The AI summary path treats normal 403/404 as no available summary while preserving Cloudflare challenge errors for host recovery.
10. If Rust returns `CloudflareChallenge` for an authenticated operation, keep the current session snapshot and recover through a host-owned WebView. iOS currently deletes stale `cf_clearance`, waits for the login-readiness gate, syncs the browser cookie batch into Rust, and retries the blocked operation. Android keeps the challenge WebView visible after `cf_clearance` appears: topic detail embeds `https://linux.do/t/{topicId}` below the toolbar, while other surfaces open `https://linux.do/`; both paths sync the browser cookie batch into Rust so subsequent native reads can continue without closing the WebView.
11. On explicit logout, prefer `logout_remote`, then fall back to `logout_local`, clear the persisted session, and remove host-side WebView auth cookies so the native shell and platform browser state agree.
12. Use `notification_state`, `fetch_recent_notifications`, `fetch_notifications`, `mark_notification_read`, and `mark_all_notifications_read` for the shared in-app notification data path; keep OS-level/system notification presentation on the hosts.

Third-party OAuth provider policy is a separate boundary from Fire's WebView profile. Providers such as Google can reject embedded user agents even when the host uses a Safari-compatible UA; supporting those providers requires a system authentication session / Safari fallback and an explicit way to import the resulting LinuxDo session back into the Fire cookie/session pipeline.

File ownership convention:

- Native hosts provide a platform workspace root to Rust:
  - iOS: `Application Support/Fire`
  - Android: `filesDir/fire`
- Rust keeps this workspace root for shared file concerns that belong to the shared layer.
- The current Rust-owned file layout inside that workspace is:
  - `logs/` for Mars Xlog output
  - `diagnostics/fire-readable.log` for a plaintext tracing mirror
  - `diagnostics/support-bundles/` for locally exported diagnostics bundles
  - `cache/xlog/` for Xlog cache and mmap spill files
  - `session.json` for the persisted session snapshot triggered by the host shell
- iOS now also owns `ios-apm/` under the same workspace root for beta crash/APM files. That directory is explicitly host-owned and must not be treated as shared Rust diagnostics state.
- Debug builds may also mirror shared logs into the platform console for local development, but release builds keep shared logging file-only through Xlog/readable-log artifacts.
- `session.json` remains host-triggered persistence under that workspace root.
- iOS currently treats `session.json` as a full-fidelity development cache and stores the same-site browser cookie batch in Keychain, including expiry metadata and refreshed auth-cookie state observed by Rust, while letting Rust-owned persistence revisions decide when those writes are actually necessary.
- iOS exposes the Rust-owned captured browser user agent on `SessionState` and uses it for the offscreen Cloudflare Turnstile runtime; if the session has no captured user agent yet, login and challenge WebViews use the shared Mobile Safari-style fallback profile.
- Android currently still restores the full snapshot from `session.json` until its secure-cookie migration lands.

Cooked-content parsing is now shared in Rust. `fire-core` parses Discourse `cooked` HTML with `scraper` on top of `html5ever`, producing a flat cooked-HTML AST plus shared plain text, image URLs, and link URLs; the top-level `fire_uniffi` namespace exposes that as `parseCookedHtml`. Native rendering and layout remain host-owned: iOS still renders its richer native cooked-content surface from host caches, while Android topic detail now consumes the same Rust AST through `FireCookedHtmlRenderer` for native paragraphs, headings, quotes, lists, code blocks, details/spoilers, link spans, and media fallback cards.
