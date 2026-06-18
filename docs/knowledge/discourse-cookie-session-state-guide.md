# Discourse Cookie And Session State Guide

This guide is the stack-neutral contract for LinuxDo cookie state, WebView
boundary sync, and duplicate-cookie recovery. It captures the v0.4 cookie
behavior Fire needs without depending on any Flutter, Dart, or reference-project
source file.

Rust owns canonical cookie state. Platforms own native WebView cookie store
mechanics.

## 1. Goals

Cookie handling must:

- Preserve enough metadata to write browser-compatible cookies back to WebView.
- Prevent stale WebView bulk reads from overwriting fresh network or challenge
  cookies.
- Keep `_t` and `_forum_session` host-only for `linux.do`.
- Collapse duplicate critical cookie variants to one winner.
- Support exact deletion that bypasses freshness arbitration.
- Self-heal common logged-out responses before declaring the user logged out.

## 2. Stores

| Store | Owner | Purpose |
|---|---|---|
| Canonical cookie state | Rust | Request headers, freshness arbitration, persistence |
| WebView cookie store | Platform | Browser login, hCaptcha, Cloudflare |
| Secure credential/session storage | Platform + Rust boundary | Username, encrypted persisted session data |

The WebView store is never the authority by itself. WebView reads are inputs to
Rust arbitration.

## 3. Canonical Cookie Fields

Canonical cookies should include:

```text
name
value
domain
path
host_only
secure
http_only
same_site
partition_key
partitioned
expires_at
max_age
creation_time
last_access_time
version
source
raw_set_cookie
origin_url
```

`same_site` values:

```text
unspecified
lax
strict
none
```

Platform WebView APIs may omit `SameSite` even when the cookie was originally
set with it. When extracting `cf_clearance` and no explicit value is visible,
Fire treats it as `none` because Cloudflare clearance is expected to be
`SameSite=None; Secure` for the LinuxDo challenge flow. Raw network
`Set-Cookie` metadata remains authoritative when available.

`source` values should distinguish at least:

```text
network_set_cookie
webview_login
webview_challenge
webview_bulk_read
manual_restore
unknown
```

## 4. Storage Identity

Canonical storage identity is:

```text
(name, normalized_domain, path, partition_key)
```

`host_only` is metadata, not part of the storage key.

Reason: platform WebView APIs do not consistently expose host-only state. If
host-only is part of the key, the same logical cookie can be stored twice and the
browser may send the stale value first.

`normalized_domain` rules:

- If a cookie has `Domain=.linux.do`, normalize to `linux.do` and
  `host_only=false`.
- If a cookie has no Domain attribute and origin `https://linux.do/`, normalize
  to `linux.do` and `host_only=true`.
- A bare domain returned by WebView APIs must not automatically become a
  Domain-cookie. Leading dot or explicit platform metadata is required to mark
  `host_only=false`.

## 5. Freshness

Trusted writes:

- HTTP `Set-Cookie` from the Rust API client.
- Cookies extracted after successful WebView login.
- Confirmed fresh cookies from Cloudflare verification.
- Explicit migration/repair writes.

Untrusted writes:

- Generic WebView bulk reads.
- Low-metadata `CookieManager.getCookie()` snapshots.
- Any snapshot collected without a known login/challenge boundary event.

When saving a cookie with an existing storage key:

1. If the write is trusted and the value changed, increment `version`.
2. If the write is trusted and the value is unchanged, keep `version`.
3. If the write is untrusted, replace only when the incoming cookie is fresher.
4. Freshness order is `version`, then later `expires_at`, then later
   `creation_time`.
5. Replacements inherit the old `creation_time` for stable serialization.

Expired-cookie writes are not a reliable delete mechanism. Explicit delete must
bypass freshness checks.

## 6. Explicit Delete

`delete_by_name(uri, name)` removes all cookies with the given name that are
applicable to the URI host:

- exact host match;
- cookie domain is a parent domain of the host;
- cookie domain is a child domain of the host when cleaning a site family.

This operation is a business intent and must not be rejected because the delete
marker is older than the stored cookie.

Use explicit delete for stale `cf_clearance` cleanup, logout of identity cookies,
and nuclear reset preparation.

## 7. Request Cookie Header

When building a request cookie header:

1. Filter cookies by scheme, domain, path, expiry, and partition constraints.
2. Sort by longer path first.
3. Prefer more specific domains.
4. Prefer host-only over domain cookies when otherwise equal.
5. Preserve stable creation order for ties.
6. Ensure only one value per critical cookie name is sent.

Critical cookie names include at least:

```text
_t
_forum_session
cf_clearance
_cfuvid
h_captcha_temp_id
```

## 8. WebView Boundary Sync

There are two authoritative directions.

### Path A: HTTP Response To WebView

When Rust receives `Set-Cookie` from normal API traffic:

1. Save cookies into canonical state as trusted.
2. For critical cookies, immediately enqueue or execute a WebView write.
3. Sweep the relevant name to keep the WebView store unique.

### Path B: WebView Login Or Challenge To Rust

When a WebView flow itself performed the network request:

1. Do not expect Rust to have seen the `Set-Cookie` header.
2. Extract cookies from the live WebView before disposal.
3. Preserve native cookie metadata when the platform exposes it. Android should
   use `CookieManagerCompat.getCookieInfo()` for full WebView extraction and fall
   back to plain `CookieManager.getCookie()` name/value snapshots only as
   low-confidence input. Low-confidence session cookies must not complete login
   unless an explicit device constraint allows it. Cloudflare challenge recovery
   may use a low-confidence snapshot only after the platform has independently
   confirmed the accepted `cf_clearance` value, and Rust must reject any other
   `cf_clearance` value from that snapshot.
4. Send those cookies to Rust with source `webview_login` or
   `webview_challenge`.
5. Mark the write trusted only when the flow boundary confirms freshness.
6. For Cloudflare challenge completion, pass the accepted `fresh_cf_clearance`
   value and let Rust reject any `cf_clearance` cookie with a different value.
7. Challenge completion is a merge, not an authoritative login-state replace.
   If that WebView snapshot lacks `_t` or `_forum_session`, Rust must preserve
   the existing Discourse identity cookies.
8. Sweep critical names after applying the cookies.

Generic WebView reads outside these boundary events are untrusted. They may be
used as an authoritative login-state replacement only when the host resync batch
contains both active identity cookies, `_t` and `_forum_session`.

## 9. Cookie Priming

Before opening a login, challenge, or trusted in-app WebView:

1. Ask Rust for a priming payload for `https://linux.do/`.
2. For each critical cookie being primed, delete existing WebView variants for
   that name before writing the canonical cookie.
3. Re-read canonical state immediately before each async write batch.
4. Write raw `Set-Cookie` headers when available.
5. Use structured fields to reconstruct `Set-Cookie` only when raw headers are
   absent.
6. Do not reinsert a cookie Rust deleted during the priming operation.
7. Deduplicate repeated priming for the same URL unless invalidated.

Priming must be invalidated after CF cleanup, explicit delete, logout, and any
trusted update to a critical cookie.

## 10. Session Cookie Sentinel

The sentinel enforces this postcondition:

```text
For each critical cookie name and WebView URL:
  ensure_unique => WebView variant count <= 1
  delete        => WebView variant count == 0
```

Concurrency rules:

- Serialize sweep operations per cookie name.
- Allow different names to sweep concurrently.
- Use a bounded lock timeout.
- Check auth/session generation before expensive reads, before writes, and after
  writes.
- Cancel in-flight sweeps when auth generation advances.

## 11. Winner Selection

When WebView contains multiple variants for the same name:

1. If Rust has a canonical value and WebView has exactly one matching variant,
   use the Rust canonical cookie as winner.
2. If Rust has a canonical value and WebView has multiple variants including
   that value, choose the best non-matching WebView variant as winner. This
   handles cases where WebView received a fresher value that Rust has not seen.
3. Prefer non-empty values over empty values.
4. Prefer unexpired cookies over expired cookies.
5. Prefer host-only over domain cookies when the field is available.
6. Prefer later expiry.
7. Prefer longer value.

When a WebView value wins but Rust has canonical metadata, write back using
Rust's metadata and the WebView winner value. This preserves domain, path,
SameSite, Secure, HttpOnly, and Partitioned fields even on platforms whose
WebView only exposes `name=value`.

If sweep cannot reduce variants to one, perform nuclear reset.

## 12. Nuclear Reset

Nuclear reset for a URL:

1. Build the union of cookie names known by Rust and WebView.
2. Delete all WebView variants for those names using exact native delete when
   available.
3. Re-prime WebView from Rust canonical state.
4. Verify every applicable canonical cookie has at most one WebView variant.

Nuclear reset is a recovery path, not the normal write path.

## 13. Self-Healing

Before treating an authenticated response as logout, Rust should attempt cookie
self-healing for:

```text
401
419
strong discourse-logged-out signals
```

Healing sequence:

1. Sweep all critical names and retry the request.
2. Repeat sweep retry up to the configured small retry count.
3. If still failing, nuclear reset and retry once.
4. If still failing, fall back to conservative session probe/logout handling.

Each healed retry must carry a recursion guard so the interceptor cannot heal
its own retry indefinitely.

## 14. Persistence And Reload

Persist only non-expired persistent cookies. Session cookies may remain in
memory unless platform secure storage policy requires otherwise.

When multiple processes, isolates, or app extensions can write cookie storage:

- Serialize read-modify-write inside one process.
- Use unique temporary file names for atomic writes.
- Cache the last written content and skip no-op writes.
- Provide `reload_persisted_cookies` so foreground state can merge disk changes
  without dropping in-memory session cookies.

Disk wins for persistent cookies during reload. In-memory session cookies remain
unless a disk cookie with the same storage key exists.
