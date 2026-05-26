# Read-Path Login Recovery Resync

This document describes the v0.1.0 hotfix that prevents passive reads (home feed and topic detail) from prematurely tearing down the session and presenting the WebView login when Discourse rotates auth cookies between requests. The two earlier auth incidents are still scoped narrowly:

- Cookie deletion misread as logout: [ios-auth-cookie-invalidation-fix.md](ios-auth-cookie-invalidation-fix.md)
- Partial auth rotation before an authenticated write: [ios-auth-cookie-rotation-recovery-plan.md](ios-auth-cookie-rotation-recovery-plan.md)

## Incident Shape

- Users on the v0.1.0 TestFlight build reported that a successful day of browsing would suddenly drop them back into the WebView login flow.
- The most common triggers were a passive home feed pull or a topic detail open, not an explicit write.
- The shared layer correctly classified `403 not_logged_in` and `discourse-logged-out` responses as `LoginRequired`, but on the read path iOS treated every `LoginRequired` as authoritative logout evidence.
- Empirically, a fraction of those errors were transient: the WebKit cookie store already held a freshly rotated `_t` / `_forum_session` while the shared Rust cookie jar had not yet observed the rotation.
- There was no read-path equivalent of the authenticated-write host resync, so a single transient mismatch was enough to nuke the session.

## Landed Route

### Single host resync per session epoch on the read path

- `FireAppViewModel.attemptReadPathLoginRecovery(operation:error:)` is the new read-side recovery entry. It only reacts to `FireUniFfiError.LoginRequired`.
- The recovery is single-flight: at most one resync runs per shared session epoch, and the same epoch will not be retried after one attempt fails. This bounds the work even under bursty error storms.
- The recovery flow:
  1. Read the current shared session epoch through `FireSessionStore.currentSessionEpoch()`.
  2. Pull the latest LinuxDo browser-context cookies through the existing `FireWebViewLoginCoordinator.platformCookiesForSessionResync()` helper.
  3. Push them through `FireSessionStore.applyPlatformCookies(_:)`.
  4. Read the post-resync epoch. If it advanced, the resync actually rotated auth cookies and the caller may retry the original read once. If it did not advance, the resync produced no new auth state and the caller must fall through to the existing `handleRecoverableSessionErrorIfNeeded` reset path.
- Diagnostics breadcrumbs and `auth` host log lines record both the success and the no-op cases for support triage.

### Read-site usage

- `FireHomeFeedStore.loadTopics` and `FireTopicDetailStore.loadTopicDetail` call the new helper before falling back to the legacy reset path.
- Both call sites release their in-flight gates (`isLoadingTopics` / `loadingTopicIDs`) before recursing, and the recursive load passes `force: true` so cache or dedupe guards do not short-circuit the retry.
- All other call sites of `handleRecoverableSessionErrorIfNeeded` are unchanged. Writes still rely on the existing `runAuthenticatedWritePreflight` flow.

### State management

- A new `readPathLoginRecoveryAttemptedEpochs` set lives on `FireAppViewModel` and is cleared in two places:
  - When a resync rotates the session into a new epoch, only the markers tied to that new epoch are kept.
  - When `resetSessionAndPresentLogin` runs, the set is cleared completely so a future cold-start session can recover again.
- A `readPathLoginRecoveryTask` lives alongside it for the in-flight coalescing, scoped to a specific `readPathLoginRecoveryEpoch`.

## Boundaries

- Do not rotate the session from the read path itself: the helper only consumes platform cookies the WebView already holds, never opens a new auth WebView.
- Do not bypass `handleRecoverableSessionErrorIfNeeded` for non-`LoginRequired` errors: stale responses, Cloudflare challenges, and generic HTTP errors keep their existing handlers.
- Do not retry more than once per session epoch on the read path: the call site falls back to the original reset/login flow after that, so we do not mask repeated server-side invalidation.
- Do not change the shared Rust invalidation policy: this hotfix only adds a host-side recovery attempt before the existing logout/login flow runs.

## Why This Matters

- It removes the v0.1.0 TestFlight failure mode where one transient `not_logged_in` response on a passive read kicked authenticated users back to the WebView.
- It keeps the existing strong-invalidation handling intact, so explicit server logout still wins.
- It mirrors the design choice of the authenticated-write recovery: `FireSessionStore` and `FireAppViewModel` together own host-side recovery policy, leaving Rust as the source of truth for shared session state.
