# Cloudflare Silent Refresh in `performWithCloudflareRecovery`

This page documents how Fire's iOS host narrows the gap between observing a
Cloudflare challenge and surfacing the manual verification page. It is a
companion to [ios-auth-cookie-rotation-recovery-plan.md](ios-auth-cookie-rotation-recovery-plan.md).

## Symptom

Tapping into a topic detail occasionally surfaces the Cloudflare verification
page or, in the worst case, drops the user back to the login flow even though
the local session has not been invalidated. The triggering request is the read
path that opens the topic:

- `GET /t/{topicId}.json` (or `GET /t/{topicId}/{postNumber}.json`).

`POST /message-bus/{clientId}/poll` is **not** the trigger. Fire keeps a single
foreground long-poll task across the whole app. Opening a new topic only adds
`/topic/{id}`, `/topic/{id}/reactions`, and the matching presence channel to
the next poll iteration; it does not start a new poll request.

## Why the topic detail GET ends in a CF challenge

The iOS host already serializes all read paths through
`FireAppViewModel.performWithCloudflareRecovery`. The previous flow was:

1. `work()` → fails with `FireUniFfiError.CloudflareChallenge`.
2. `syncPlatformCookiesFromWebViewStore()` mirrors the current
   `WKWebsiteDataStore` cookies into the shared Rust session.
3. `work()` retry → still a Cloudflare challenge.
4. Fall back to `beginCloudflareRecoveryAndWait`, which clears
   `cf_clearance` from WebView and shows the manual verification page.

Step 2 only helps when the WebView already holds a fresher
`cf_clearance` than the Rust session. The most common production case is the
opposite: the Cloudflare clearance has expired in **both** stores, so step 3
fails for the same reason, and the user sees the manual verification page on
every topic open until they complete it.

`FireCfClearanceRefreshService` is supposed to catch this. It runs a hidden
WKWebView that drives Turnstile and posts to
`/cdn-cgi/challenge-platform/h/g/rc/{chl}` in the background, then mirrors the
rotated cookies back through `loginCoordinator.refreshPlatformCookies()`. But
the service is purely time-driven: it only runs when its periodic schedule
ticks or when `updateSession`/`setSceneActive` reconfigures it. A user who
opens a topic right after the previous clearance expired loses the race.

## Landed Behavior

`performWithCloudflareRecovery` now adds one more recovery step before falling
back to the interactive flow:

1. `work()` (unchanged).
2. `syncPlatformCookiesFromWebViewStore()` (unchanged) and a retry.
3. **Silent on-demand refresh**: call
   `FireCfClearanceRefreshService.triggerOneShotRefresh()` and await the
   next successful Turnstile → `rc` round trip (or a timeout).
4. If the silent refresh succeeded, retry `work()` once more.
5. Only if step 4 still raises `CloudflareChallenge` (or step 3 reports the
   service is unavailable / exhausted / preconditions are not met) does the
   flow fall through to `beginCloudflareRecoveryAndWait` and the manual
   verification page.

The silent refresh reuses the existing background runtime; it does not spawn a
new WebView, does not duplicate the Turnstile state machine, and does not
bypass the `interactiveRecoveryActive` interlock. The interactive recovery
flow is still the strict source of truth for "user must verify".

### `FireCfClearanceRefreshService.triggerOneShotRefresh(timeout:)`

The new public entry point on the service:

- Returns the rotated `SessionState` once the next Turnstile cycle succeeds.
- Throws `FireCfClearanceRefreshError.preconditionsNotMet` when the service
  cannot run (no `turnstileSitekey`, no existing `cf_clearance`, scene not
  active, or an interactive Cloudflare recovery is already in progress).
- Throws `serviceUnavailable` when the runtime is torn down (e.g. session
  readiness drops while the caller is waiting).
- Throws `exhausted` after `maxConsecutiveFailures` consecutive failures.
- Throws `timedOut` when the caller's deadline elapses (default 20s).
- Throws `CancellationError` if the caller's task is cancelled.

The waiter list is keyed by a `UUID` and resolved by the existing
`onSessionRefreshed` plumbing, so concurrent recovery attempts share the same
runtime cycle.

## Boundaries

- The silent refresh path must not change failure classification. A request
  that maps to `LoginRequired` (server-side `discourse-logged-out` or
  `error_type: "not_logged_in"`) still bypasses recovery and reaches
  `handleRecoverableSessionErrorIfNeeded`.
- `triggerOneShotRefresh` does not bypass `interactiveRecoveryActive`. While
  the manual verification page is on screen, the refresh service stays paused
  and the silent path returns `preconditionsNotMet` immediately.
- The fallback to the interactive flow remains identical to before. Anything
  that used to surface a verification page still does, only after the silent
  attempt has been given one chance.

## Verification

- `cargo test -p fire-core`
- `xcodebuild -scheme Fire test` (covers `FireTopicDetailStoreTests`,
  `FireAppViewModelTests`, and the full iOS suite)

## Related Documents

- [ios-auth-cookie-rotation-recovery-plan.md](ios-auth-cookie-rotation-recovery-plan.md):
  the partial-auth-rotation recovery design that the silent refresh sits on
  top of.
- [ios-auth-cookie-invalidation-fix.md](ios-auth-cookie-invalidation-fix.md):
  earlier fix that disambiguates server-driven logout from cookie deletion.
- [ios-auth-alignment-plan.md](ios-auth-alignment-plan.md): broader auth
  alignment plan.
