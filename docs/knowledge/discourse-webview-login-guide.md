# Discourse WebView Login Guide

This guide is the stack-neutral contract for LinuxDo password login. It captures
the v0.2.18 behavior Fire relies on without depending on any Flutter, Dart, or
reference-project source file.

Password login must not load the Discourse Ember `/login` application as the
normal path. The authoritative path is a native login form plus a minimal WebView
document that performs the login requests through the WebView network stack.

## 1. Goals

The login boundary must produce:

- Valid `https://linux.do` cookies, especially `_t` and `_forum_session`.
- Current Cloudflare clearance cookies such as `cf_clearance` and `_cfuvid`.
- The WebView user agent used for login and challenge verification.
- A classified `POST /session.json` result.
- A current user session after bounded login finalization.

The login boundary must not:

- Fetch `/session/csrf` through the Rust/OpenWire API client for password login.
- Depend on navigation to `/` as proof of login.
- Dispose the login WebView before extracting session cookies.
- Duplicate Discourse login result parsing separately in Swift and Kotlin.

## 2. Ownership

| Area | Owner | Notes |
|---|---|---|
| Native username/password form | Platform | iOS and Android own UI, input validation, credential save prompts |
| hCaptcha rendering | Platform WebView | Use a minimal same-origin WebView document |
| `/session/csrf`, hCaptcha create, `/session.json` | Platform WebView | Requests must use WebView TLS/cookie behavior |
| Login result parsing | Rust | One shared parser for iOS and Android |
| Cookie arbitration and session state | Rust | Platform only extracts/writes native WebView cookies |
| Cloudflare challenge UI | Platform | Rust requests verification and receives fresh cookies |

## 3. Preconditions

Before opening the login dialog:

1. Restore Rust canonical cookies from secure/persistent storage.
2. Check whether Rust has a usable `cf_clearance` for `https://linux.do`.
3. If no clearance exists, run manual Cloudflare verification first and sync the
   confirmed fresh clearance through the trusted challenge-completion path.
4. Prime the login WebView cookie store from Rust before the first login fetch.

The WebView cookie store must be treated as not reliably shared across separate
WebView instances. Always prime the specific dialog instance that will issue the
login fetches.

## 4. Minimal WebView Document

The login dialog loads a small HTML document with base origin
`https://linux.do/`. It may be delivered by a `data:` URL or by equivalent
platform APIs such as `loadHTMLString(..., baseURL:)` or
`loadDataWithBaseURL(...)`.

The document contains only:

- hCaptcha script loading from `https://js.hcaptcha.com/1/api.js`.
- An hCaptcha container with the LinuxDo site key.
- Bridge callbacks for hCaptcha success, error, and expiry.
- One login function callable by native code.

The document must not load the Discourse Ember application.

LinuxDo's current hCaptcha site key is:

```text
a776b4ac-8c4c-441e-986a-c6ee9ed8cf08
```

## 5. JavaScript Bridge

The WebView page sends these callbacks to native code:

```text
hcaptcha_pass(token)
hcaptcha_error(message)
hcaptcha_expired()
login_result({ phase, status, body })
```

The native host calls one JS function. The implementation name is platform-local,
but Fire should use `window.__fireLogin` in new code:

```text
window.__fireLogin(identifier, password, hcaptchaToken, secondFactorToken)
```

Arguments:

| Argument | Type | Meaning |
|---|---|---|
| `identifier` | string | Username or email |
| `password` | string | Password |
| `hcaptchaToken` | string or null | Token from `hcaptcha_pass`; null on 2FA retry |
| `secondFactorToken` | string or null | TOTP code for retry; null on first attempt |

All string arguments must be injected with JSON encoding, not string
concatenation.

`login_result.phase` values:

| Phase | Meaning |
|---|---|
| `csrf` | `GET /session/csrf` failed |
| `hcaptcha` | all hCaptcha create endpoints failed |
| `session` | `POST /session.json` returned |
| `exception` | JS exception or network exception before a structured response |

## 6. Request Contract

All login requests use:

```text
credentials: include
cache: no-store for /session/csrf
```

Do not manually set `Cookie`, `User-Agent`, `Origin`, `Referer`, or `Sec-*`
headers in JS. Let the WebView engine own those browser headers.

### 6.1 Fetch CSRF

```http
GET /session/csrf
X-Requested-With: XMLHttpRequest
Accept: application/json
```

Expected success:

```json
{
  "csrf": "..."
}
```

Any non-`200` response is reported as:

```json
{
  "phase": "csrf",
  "status": 403,
  "body": "..."
}
```

### 6.2 Create hCaptcha Session

This step runs only when `hcaptchaToken` is non-null. It exchanges the hCaptcha
token for the short-lived `h_captcha_temp_id` cookie.

Try endpoints in order. A caller-provided endpoint may be inserted first; the
built-in fallbacks must remain in this order:

```text
<configured hcaptcha create endpoint, when present>
/captcha/hcaptcha/create.json
/hcaptcha/create.json
```

Request:

```http
POST <endpoint>
Content-Type: application/x-www-form-urlencoded
X-CSRF-Token: <csrf>
X-Requested-With: XMLHttpRequest

token=<url-encoded hcaptcha token>
```

Behavior:

- `200` means success and the flow continues.
- `404` means the endpoint path is unavailable; try the next endpoint.
- Any other status stops the flow and reports phase `hcaptcha`.
- Network exceptions on one endpoint may try the next endpoint; if all fail,
  report phase `hcaptcha`.

### 6.3 Submit Session

```http
POST /session.json
Content-Type: application/x-www-form-urlencoded
X-CSRF-Token: <csrf>
X-Requested-With: XMLHttpRequest
Accept: application/json

login=<identifier>&password=<password>
```

For TOTP retry:

```http
login=<identifier>&password=<password>&second_factor_token=<code>&second_factor_method=1
```

`second_factor_method=1` means TOTP. Backup codes and security keys are separate
future capabilities.

The JS bridge reports the raw response as phase `session` regardless of whether
the body is success or a Discourse login error. Rust classifies the body.

## 7. Session JSON Classification

Rust parses `POST /session.json` response bodies.

If the body is not JSON, classify it as unknown failure:

```text
kind = unknown
message = "Discourse returned non-JSON: HTTP <status>"
```

Known `reason` values:

| `reason` | Classification | Extra fields |
|---|---|---|
| `invalid_second_factor` | `second_factor_required` | `totp_enabled`, `security_key_enabled`, `backup_enabled` |
| `second_factor` | `second_factor_required` | `totp_enabled`, `security_key_enabled`, `backup_enabled` |
| `invalid_credentials` | `invalid_credentials` | `error` message |
| `not_activated` | `not_activated` | `sent_to_email`, `current_email` |
| `not_approved` | `not_approved` | `error` message |
| `expired` | `password_expired` | `error` message |
| other | `unknown` | `error` or `reason=<value>` |

If `error` exists and `user` is absent, classify as `unknown` with the error
message.

Otherwise classify the response as success.

## 8. Second Factor Flow

When Rust returns `second_factor_required`:

1. Platform presents a TOTP dialog.
2. Platform keeps the same live login WebView instance.
3. Platform calls `window.__fireLogin(identifier, password, null, code)`.

The hCaptcha token is not sent again. The previous hCaptcha create step already
wrote `h_captcha_temp_id`, and that cookie is expected to remain valid for the
short retry window.

If the server reports backup-code or security-key-only state, Fire may show a
clear unsupported-method error until those methods are implemented.

## 9. Login CSRF Cloudflare Retry

If phase `csrf` returns a Cloudflare challenge response with explicit
Cloudflare body markers:

1. Retry this recovery path at most once for the current login attempt.
2. Run manual Cloudflare verification in a platform WebView, preferring the
   same-origin `/challenge` URL.
3. Wait briefly for WebView cookie propagation.
4. Extract all relevant WebView cookies, including `cf_clearance` and `_cfuvid`.
5. Save confirmed challenge cookies into Rust as trusted writes, passing the
   accepted `fresh_cf_clearance` so stale WebView variants are rejected.
6. Invalidate the login dialog priming state.
7. Re-prime the same live login WebView.
8. Re-run `window.__fireLogin` with the same hCaptcha and second-factor args.

The hCaptcha token can be reused because phase `csrf` fails before the hCaptcha
create request consumes it.

## 10. Cookie Priming

Before the first login fetch and after any CF retry, platform code must write
Rust's canonical cookie payload into the login WebView store.

Priming rules:

- Read the latest canonical cookie state immediately before writing.
- Do not reuse a stale payload across async waits.
- Skip cookies that Rust has explicitly deleted.
- Use raw `Set-Cookie` strings when Rust provides them.
- Fall back to structured cookie fields only when raw headers are unavailable.
- Treat Android `name=value` snapshots as low confidence and let Rust provide
  metadata when writing cookies back.

## 11. Successful Handoff

On login success:

1. Extract `_t`, `_forum_session`, `cf_clearance`, `_cfuvid`, and related
   LinuxDo cookies from the live WebView.
2. Send those cookies to Rust as trusted WebView-login cookies.
3. Include the browser user agent when available.
4. Call the single Rust login finalizer before disposing the WebView.

Rust finalization:

1. Advances the auth/session generation and cancels older in-flight work.
2. Applies trusted cookies to canonical cookie state.
3. Reads `_t` from canonical cookies and updates in-memory token state.
4. Persists the username through the platform-secure storage boundary.
5. Hydrates preloaded data when available, otherwise refreshes bootstrap over
   HTTP.
6. Uses an 8 second timeout for login-ready refresh.
7. Always notifies login-ready in `finally` semantics.

The UI must never remain permanently loading because bootstrap refresh failed or
timed out after a successful cookie handoff.

## 12. Deprecated Normal Path

The older password-login design loaded `https://linux.do/login`, injected page
scripts, and inferred success from page state or navigation. That path is not the
normal Fire implementation target.

Browser login surfaces may still be needed later for distinct features such as
OAuth provider flows, passkeys, or email-link login. Those features must be
designed separately and must not reintroduce the Ember `/login` page as the
password-login fallback.
