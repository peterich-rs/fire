# Discourse Cloudflare Challenge Guide

This guide is the stack-neutral contract for Cloudflare verification around the
LinuxDo Discourse site. It is aligned with Fire's Rust/native implementation and
with the current observed LinuxDo/Cloudflare behavior used by the reference
client.

Cloudflare verification is a browser-owned operation. Rust detects and
orchestrates challenge recovery, but platform WebViews complete the challenge
and extract cookies.

## 1. Goals

Cloudflare handling must:

- Detect challenge responses on both `403` and `429`.
- Use Cloudflare headers as the highest-confidence signal.
- Complete verification in a platform WebView.
- Treat a verification page that is no longer challenged as complete. A new
  `cf_clearance` is optional; the API retry is the authority for recovery.
- Sync any confirmed `cf_clearance` and related cookies to Rust as a best-effort
  trusted write.
- Freeze ordinary business requests while verification is active.
- Let concurrent CF victims join one shared verification and each retry once.
- Keep `cf_clearance` one-way: WebView → Rust jar only. Never prime or sweep
  jar copies back into the browser store.

## 2. Detection

A response is a Cloudflare challenge when:

1. The response status is `403` or `429`.
2. The response is from Cloudflare, usually `Server: cloudflare`.
3. One of these signals is present:
   - `cf-mitigated: challenge`
   - challenge HTML/body markers such as `cf_chl_opt`, `cf-turnstile`,
     `challenge-running`, or `challenge-stage`
   - `challenge-platform` with Cloudflare context
   - `Just a moment` with Cloudflare or challenge context

Do not classify every `429` as Cloudflare. LinuxDo and Discourse can return
ordinary rate-limit responses. The CF path requires Cloudflare-specific headers
or body markers.

Do not require `text/html` when `cf-mitigated: challenge` is present. API
requests can receive `text/plain` challenge bodies.

## 3. Request Modes

Rust classifies challenge presentation by mode:

| Mode | Meaning | UI behavior |
|---|---|---|
| `silent` / background | MessageBus, timings, bootstrap refresh, notification polls | Do not open a new challenge UI. Soft-fail, or join an already running foreground verification |
| `foreground` / data / action | Visible UI data or user-initiated work | May open manual verification immediately and bypass cooldown |

Only foreground requests may start a new platform challenge. Background traffic
must never steal focus.

## 4. In-Progress State And Join

Rust owns `cf_in_progress`. It becomes true before platform verification starts
and false after the verification page finishes or is cancelled. A finished page
does not prove that native API traffic has recovered.

While `cf_in_progress` is true:

- Ordinary API requests that have not yet been dispatched are blocked before
  send (`CloudflareChallengeInProgress`).
- Requests that already received a CF challenge response join the active
  verification instead of opening another WebView.
- After shared success, every joined request retries itself once with
  `skip_cf_block`.
- MessageBus polling / timings should remain non-foreground so they do not open
  UI and do not create clearance write-back storms.
- Internal challenge retries must be marked to avoid recursion.

This matches browser behavior: once a page is behind a challenge, fresh business
traffic does not continue with stale cookies, but concurrent victims of the same
challenge share one verification.

## 5. Manual Verification

Manual verification opens a platform WebView on a trusted LinuxDo origin.

Recommended completion checks:

1. Snapshot every visible `cf_clearance` value before verification: the jar
   backup plus all WebView variants, including partitioned leftovers. Use this
   set only to recognize a newly issued value, not as a success gate.
2. Delete stale `cf_clearance` cookies from the platform WebView store when
   starting a fresh verification. Active delete is allowed; jar→WebView rewrite
   is not.
3. Prefer loading the same-origin bare `/challenge` URL in the WebView.
4. Detect active challenge markers in the page
   (`cf_chl_opt`, `cf-turnstile`, `challenge-running`, `challenge-stage`, etc.).
5. After CF passes, the browser often navigates back to bare `/challenge`. That
   path is **not** a real Discourse page. Treat a main-frame verification URL
   that reaches the origin with **404** and **without**
   `cf-mitigated: challenge` as "the verification entry is clear". A **2xx**
   document on `/challenge` is usually the Cloudflare challenge page itself and
   must not auto-finish. 403/429 and other ambiguous statuses are not a pass
   by themselves. An empty first paint with no challenge markers is also not a
   pass; wait until the challenge was actually visible or the origin 404
   appears.
6. Cover the WebView with a completion overlay (`正在完成验证…`) as soon as
   post-pass `/challenge` navigation or origin-not-found markers are observed so
   the user never sees Discourse's "page does not exist" body.
7. Accept page completion when the loaded verification document is no longer an
   active challenge after it was seen, including the origin 404 case. The origin may pass the
   browser through without issuing a new cookie. Do **not** wait for a new
   `cf_clearance`, and do **not** require a homepage reload probe.
8. Sync any currently visible Cloudflare cookies to Rust as a best-effort
   trusted write. If a confirmed new `cf_clearance` is present, pass it as
   `fresh_cf_clearance` / `accept_values`. Missing cookie must not fail the
   page or block the API retry.
9. On cancel/failure, restore only the WebView-local clearance backup taken at
   step 1. Do not re-prime clearance from Rust jar state.

Related cookies include `cf_clearance` and `_cfuvid`. A challenge WebView
snapshot may also contain Discourse identity cookies, but challenge completion
must merge those inputs into Rust's existing session; it must not treat a partial
WebView snapshot as proof that `_t` or `_forum_session` disappeared.

## 6. `cf_clearance` One-Way Flow

`cf_clearance` is authored only by Cloudflare inside a real browser/WebView.

Required rules:

- WebView → Rust jar sync is allowed and expected.
- Rust jar / canonical store → WebView write-back is forbidden for
  `cf_clearance` during priming, sweep, nuclear reset, or ordinary cookie push.
- Challenge start may delete WebView `cf_clearance` to force a fresh challenge.
- Challenge cancel may restore the WebView backup captured before that delete.
- If multiple `cf_clearance` variants exist, keep the healthy jar incumbent.
  Do not rotate by later `expires`: challenge-page and Turnstile TTLs differ,
  and leftover CHIPS copies often expire later than the working value.

Why: replaying jar cookies through `Set-Cookie` can drop `Partitioned` and other
browser-only attributes, creating a ghost non-partitioned copy. Native code may
then send the wrong variant and produce a session that stays on CF `403` even
after restart.

## 7. Freshness Filtering

When the platform sends cookies after verification, a confirmed new
`cf_clearance` is optional. If present, the challenge result should carry only
that variant. Rust must still reject stale bulk-read values that are not the
confirmed value.

Recommended input shape:

```text
completed: true
fresh_clearance: optional string
cookies: WebView cookie snapshot; cf_clearance filtered to fresh_clearance when present
trusted: true
accept_values: { "cf_clearance": fresh_clearance } when present
```

If the platform independently confirms a fresh `cf_clearance` value but the
cookie snapshot is missing that value or only contains a variant that cannot be
sent to the site root, Rust must materialize that accepted value as a trusted
root-path `cf_clearance` for the LinuxDo origin before retrying.

The verification page finishing is not proof that native API traffic recovered.
The retry remains the authority. A clear verification entry with no new cookie
must still retry with the current jar.

## 8. Cooldown And Auto Verify

Recommended cooldown:

- Track consecutive verification failures.
- Enter cooldown after repeated failures (Fire: 3 failures → 30s).
- Foreground/manual verification may bypass cooldown.
- Reset failure count after a retry that is no longer a Cloudflare challenge.
- If the verification entry is already clear but the API retry is still a
  Cloudflare challenge, enter an immediate ineffective-clearance cooldown.
  Do not treat a missing new cookie as that failure.
- Background traffic must not open UI during cooldown.

Cooldown is a UI/rate-control policy. It must not change cookie freshness rules.

Clients may later expose an automatic verification setting. When disabled,
challenge detection should surface a manual "verify now" action instead of
opening a WebView automatically.

Hosts should distinguish challenge failure reasons when surfacing UI:

| reason | Suggested UX |
|---|---|
| `required` / `failed` | Offer retry + manual verify |
| `cancelled` | Soft message; keep manual verify |
| `cooldown` | Soft message; allow explicit manual verify bypass |
| `in_progress` | Wait / do not open a second WebView |
| `background_suppressed` | Do not steal focus; offer manual verify on visible pages |

### Platform host presentation ownership (iOS)

Automatic challenge UI has **one** owner on iOS:

1. **Network-owned present** — Rust detects a CF challenge, `begin_or_join`
   selects a single owner, and the UniFFI `CloudflareChallengeHandler` presents
   the WebView. Concurrent victims **join** that verification; new outbound
   traffic is blocked with `CloudflareChallengeInProgress` (`in_progress`).
2. **Explicit host present** — login preflight (`ensureCloudflareClearance`),
   in-login recover, and user-initiated "verify now" actions. These share the
   same process-wide presentation gate as (1) so they **join** rather than
   stack a second full-screen modal.

Host request wrappers **must not present** challenge UI:

| Wrapper | Behavior |
|---|---|
| Read-path recovery (`performWithCloudflareRecovery`) | On `in_progress`, wait for the active presentation gate (and a short jar settle), then retry once. Other CF reasons rethrow for banners / explicit manual verify |
| Write-path wrapper (`performWriteWithCloudflareRetry`) | **Passthrough** — do not wait. Rust already fails writes quickly with `in_progress`; hanging the composer is worse than a fast error the user can retry after verify |

Shared presentation gate joiners receive the owner's WebView clearance/cookie
result and intentionally ignore joiner `sessionEpoch`; each network request
retries under Rust with its own epoch after the shared challenge finishes.

`InProgress` may be folded into the same UniFFI `CloudflareChallenge` error
type as other CF failures; hosts must still branch on the reason string and
must not treat every CF error as "open WebView".

Logged-in clients should also run a hidden Turnstile clearance refresh runtime
while the app is foregrounded. Challenge response bodies may carry a Turnstile
`sitekey`; capture it into bootstrap state when missing so refresh can start.

### Clearance trust after rejection

When an API response is classified as a Cloudflare challenge, record the
`cf_clearance` value that the request actually sent as the **challenged
incumbent**. Login preflight and other "ensure clearance" checks must not skip
verification solely because a non-empty `cf_clearance` cookie still exists in
local storage.

This is not a value blacklist. The challenged incumbent may be replaced by a
later verified or naturally rotated value. A 120-second rejected window may
still block "ensure clearance" shortcuts; it must not tombstone candidate
values.

### Post-success session rebuild

After a successful challenge:

1. Merge **CF-related cookies only** into Rust (`cf_clearance`, `_cfuvid`, and
   other `cf_` / `__cf*` names). Do **not** let the challenge WebView snapshot
   overwrite `_t` / `_forum_session` identity cookies.
2. Open a short trust-settle window so the first request wave sees the jar.
3. Prefer finishing on a bare `/challenge` origin 404 (with overlay
   coverage). Avoid navigating the challenge WebView to arbitrary app routes
   that can flash unrelated UI.
4. If the user already has a login session, force bootstrap rebuild **and** a full
   app-state refresh batch (`CloudflareResolved`, bypassing normal debounce).
   Do this as soon as the verification page is clear when `current_username` or
   preloaded data is missing — do not wait for the original API retry. Hosts
   should also hydrate bootstrap when cookies exist but identity is empty.
   Manual challenge completion and network-owned completion share this path.
5. After bootstrap (success or soft failure), if auth cookies are still present,
   **force** a `/session/csrf` refresh before notifying hosts. Do not rely only
   on home HTML `<meta name="csrf-token">`:
   - bootstrap `Set-Cookie` can rotate `_forum_session` / `_t` and clear the
     cached CSRF via auth-rotation (`stale_csrf_cleared`)
   - home HTML after challenge may omit the csrf meta (interstitial residue,
     redirect, or partial page), leaving `can_write_authenticated_api` false
   - `refresh_csrf_token_if_needed` is not enough here when a pre-challenge
     token is still present but no longer valid for the rotated session
   Soft-fail CSRF refresh; write paths still have BAD CSRF clear+retry as a
   last resort. Challenge failure itself is never a logout signal.
6. Publish join success so concurrent CF victims can retry.
7. Broadcast a clearance-resolved event (`generation`, `has_login_session`,
   `can_open_message_bus`) so hosts can:
   - clear CF error banners
   - restart MessageBus when readiness allows
   - continue login finalize / retry login JS when mid-login

Note: post-challenge bootstrap / app-state refresh may be the first authenticated
requests after a long idle. If the server already expired `_t` / `_forum_session`,
auth-strike passive logout is correct behavior (session was already dead; CF did
not clear login cookies). Surface that as session expiry, not as challenge failure.

### Login-ready handoff

After WebView login cookie handoff (password or OAuth):

1. Finalize trusted cookies + username.
2. Attempt bootstrap refresh with an ~8s timeout.
3. Enter home whenever auth cookies are present, even if bootstrap is slow or
   fails (never stick on "syncing login state").
4. Post-login app-state refresh (home topic list, notifications, MessageBus)
   runs **after** login-ready / navigation and must not block the handoff UI.

## 9. Login CSRF Integration

Password login performs `/session/csrf` inside the login WebView. If that step
returns a Cloudflare challenge:

1. Treat it as a challenge response.
2. Run manual verification once.
3. Sync fresh cookies as trusted.
4. Re-prime the same login WebView for Discourse identity cookies only.
   Do not rewrite `cf_clearance` from jar state.
5. Re-run the login JS function with the original hCaptcha token.

This case is handled before hCaptcha create, so the hCaptcha token has not been
consumed.

## 10. User Agent Repair

Platforms must use a browser-compatible user agent for challenge WebViews. If a
platform WebView reports an incomplete or non-browser UA, the platform should
repair it using native browser version information where available.

The repaired UA should be returned to Rust so subsequent API requests can align
with the browser session that produced the clearance.

## 11. Verification Outcomes

| Outcome | Rust action |
|---|---|
| Verification page is no longer challenged | Merge any confirmed CF cookies, preserve Discourse identity cookies, publish shared page completion, retry owner + joined requests once |
| Retry succeeds | Treat native traffic as recovered |
| Retry is still a Cloudflare challenge | Mark the sent incumbent challenged, enter ineffective cooldown, return challenge error |
| User cancelled | Clear `cf_in_progress`, publish shared failure, return challenge error |
| Cooldown active and no manual bypass | Do not start platform UI; return soft challenge error |
| Background request with no active challenge | Do not start platform UI; return soft challenge error |
| WebView failed | Clear `cf_in_progress`, preserve existing cookies, surface retry. Missing cookie alone is not a WebView failure |
| New request arrives during active challenge | Block before dispatch (`CloudflareChallengeInProgress`) |
| Already-challenged concurrent request | Join active verification, then retry once after the shared page finishes |

Challenge failures are not logout signals. Preserve Discourse identity cookies
unless a later session probe proves logout.
