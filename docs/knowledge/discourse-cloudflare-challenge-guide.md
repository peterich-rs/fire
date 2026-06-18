# Discourse Cloudflare Challenge Guide

This guide is the stack-neutral contract for Cloudflare verification around the
LinuxDo Discourse site. It captures the v0.2.18 behavior Fire implements without
depending on any Flutter, Dart, or reference-project source file.

Cloudflare verification is a browser-owned operation. Rust detects and
orchestrates challenge recovery, but platform WebViews complete the challenge
and extract cookies.

## 1. Goals

Cloudflare handling must:

- Detect challenge responses on both `403` and `429`.
- Use Cloudflare headers as the highest-confidence signal.
- Complete verification in a platform WebView.
- Return fresh `cf_clearance` and related cookies to Rust.
- Freeze ordinary business requests while verification is active.
- Avoid resurrecting stale clearance cookies during priming or sweep.

## 2. Detection

A response is a Cloudflare challenge when:

1. The response status is `403` or `429`.
2. The response is from Cloudflare, usually `Server: cloudflare`.
3. One of these signals is present:
   - `cf-mitigated: challenge`
   - challenge HTML/body markers such as `cf_chl_opt`
   - `challenge-platform` with Cloudflare context
   - `Just a moment` with Cloudflare or challenge context

Do not classify every `429` as Cloudflare. LinuxDo and Discourse can return
ordinary rate-limit responses. The CF path requires Cloudflare-specific headers
or body markers.

Do not require `text/html` when `cf-mitigated: challenge` is present. API
requests can receive `text/plain` challenge bodies.

## 3. Request Modes

Rust should classify challenge requests by mode:

| Mode | Meaning | UI behavior |
|---|---|---|
| `silent` | Background, polling, prefetch, or telemetry request | Do not steal focus; fail softly or wait |
| `data` | Foreground data needed by visible UI | May show contextual verification |
| `action` | User-initiated action or login prerequisite | May show manual verification immediately |

Explicit manual verification actions may bypass a recent failure cooldown.

## 4. In-Progress State

Rust owns an observable `cf_in_progress` state. It becomes true before platform
verification starts and false only after verification completes, fails, or is
cancelled.

While `cf_in_progress` is true:

- Ordinary API requests are blocked before dispatch.
- MessageBus polling is paused or cancelled.
- Reading-time and timing uploads are dropped rather than queued.
- Only requests marked `skip_cf_block` may proceed.
- Internal challenge retry requests must also be marked to avoid recursion.

This matches browser behavior: once a page is behind a challenge, business
traffic does not continue with stale cookies.

## 5. Manual Verification

Manual verification opens a platform WebView on a trusted LinuxDo origin. The UI
may start hidden or contextual, but it must be able to promote to a user-visible
surface when interaction is required.

Recommended completion checks:

1. Snapshot the old `cf_clearance` before verification.
2. Delete stale `cf_clearance` cookies from the platform WebView store when
   starting a fresh verification.
3. Prefer loading the same-origin `/challenge` URL in the WebView. If a
   platform cannot build that URL, it may fall back to an origin URL on the
   same LinuxDo host.
4. Detect active challenge markers in the page.
5. Poll the WebView cookie store for `cf_clearance`.
6. Accept success only when the platform has independently confirmed a non-empty
   `cf_clearance` after the challenge page is no longer active. That value
   usually differs from the platform baseline, but it may match Rust's previous
   snapshot when the Rust jar and WebView store were out of sync.
7. Sync the accepted value and related Cloudflare cookies to Rust as trusted
   writes through the challenge-completion path.

Related cookies include `cf_clearance` and `_cfuvid`. A challenge WebView
snapshot may also contain Discourse identity cookies, but challenge completion
must merge those inputs into Rust's existing session; it must not treat a partial
WebView snapshot as proof that `_t` or `_forum_session` disappeared. Replacing
the Discourse identity pair is reserved for successful login finalization,
explicit logout, or an explicitly authoritative host resync that contains both
active identity cookies.

On Android, `CookieManagerCompat.getCookieInfo()` should be preferred because it
preserves domain/path/flag metadata. If the runtime only exposes
`CookieManager.getCookie()` name/value data, the platform may still use it to
report the independently confirmed accepted `cf_clearance` value. Rust remains
responsible for accepting only that value and treating the rest of the snapshot
as low-metadata input.

## 6. Freshness Filtering

When the platform sends cookies after verification, the challenge result should
carry only the confirmed `cf_clearance` variant. Rust must still enforce the
same rule as a second boundary check and reject stale bulk-read values.

Recommended input shape:

```text
fresh_clearance: optional string
cookies: WebView cookie snapshot with cf_clearance filtered to fresh_clearance
trusted: true
accept_values: { "cf_clearance": fresh_clearance } when present
```

If `accept_values` contains a cookie name, Rust must accept only the matching
value for that name. This prevents old WebView variants from overwriting the
fresh challenge result.

If the platform independently confirms a fresh `cf_clearance` value but the
cookie snapshot is missing that value or only contains a variant that cannot be
sent to the site root, Rust must materialize that accepted value as a trusted
root-path `cf_clearance` for the LinuxDo origin before retrying. The retry
remains the authority for whether the confirmed clearance is actually usable.

## 7. Cooldown And Auto Verify

Clients may support an automatic verification setting. When enabled, foreground
requests can show verification automatically. When disabled, challenge detection
should surface a manual "verify now" action instead of repeatedly opening a
WebView.

Recommended cooldown:

- Track verification failures.
- Enter a short cooldown after a failed or cancelled verification.
- Let explicit foreground/manual verification bypass cooldown.
- Reset cooldown after confirmed success.

Cooldown is a UI/rate-control policy. It must not change cookie freshness rules.

## 8. Login CSRF Integration

Password login performs `/session/csrf` inside the login WebView. If that step
returns a Cloudflare challenge:

1. Treat it as a challenge response.
2. Run manual verification once.
3. Sync fresh cookies as trusted.
4. Re-prime the same login WebView.
5. Re-run the login JS function with the original hCaptcha token.

This case is handled before hCaptcha create, so the hCaptcha token has not been
consumed.

## 9. User Agent Repair

Platforms must use a browser-compatible user agent for challenge WebViews. If a
platform WebView reports an incomplete or non-browser UA, the platform should
repair it using native browser version information where available.

The repaired UA should be returned to Rust so subsequent API requests can align
with the browser session that produced the clearance.

## 10. Verification Outcomes

| Outcome | Rust action |
|---|---|
| Fresh clearance returned | Merge trusted challenge cookies, preserve Discourse identity cookies, sweep critical variants, retry original foreground request once |
| User cancelled | Clear `cf_in_progress`, return a challenge-cancelled error |
| Cooldown active and no manual bypass | Clear `cf_in_progress`, return a soft challenge error |
| WebView failed without fresh cookie | Clear `cf_in_progress`, preserve existing cookies, surface retry |
| Original request obsolete by auth generation | Do not retry; discard stale result |

Challenge failures are not logout signals. Preserve Discourse identity cookies
unless a later session probe proves logout.
