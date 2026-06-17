# Discourse Client Startup Protocol Guide

This guide describes a stack-neutral startup sequence for clients that integrate
with LinuxDo's Discourse deployment. It focuses on backend-visible behavior and
data dependencies, not UI framework lifecycle, local storage APIs, or networking
library internals.

## 1. Startup Goals

A client startup should establish:

- Cookie availability for `https://linux.do`
- CSRF token, when available from bootstrap HTML
- Current authenticated user, when cookies are valid
- Site metadata and settings needed by composers and lists
- Initial topic list and topic tracking state
- MessageBus polling origin, shared session key, channels, and initial message ids
- Cloudflare challenge metadata when the HTML exposes it

## 2. Recommended Sequence

1. Initialize local configuration and restore the persistent cookie store.
2. Request `GET https://linux.do/` with `Accept: text/html`.
3. Parse bootstrap metadata and `data-preloaded`.
4. If `currentUser` is present, treat it as the current user hint.
5. If session cookies exist but no current user is present, treat the startup
   state as ambiguous without clearing cookies. A client may verify later with
   `GET /session/current.json`, but startup UI should not loop on the same
   failing verification.
6. If site metadata is incomplete, fetch `GET /site.json`.
7. Configure MessageBus using bootstrap `long_polling_base_url`,
   `shared_session_key`, and topic-tracking metadata.
8. Start foreground data requests only after the session result is known or
   intentionally treated as anonymous.

The bootstrap HTML request can run before most JSON requests because it provides
CSRF, site metadata, current-user data, and MessageBus configuration in one
response.

If this request fails during cold start but local `_t` and `_forum_session`
cookies are available, the client should preserve the local session as a
recovering authenticated state. A failed preheat/bootstrap fetch is not a logout
signal and should not force the user through login again.

## 3. Bootstrap HTML Request

```http
GET https://linux.do/
Accept: text/html
Cookie: _t=...; _forum_session=...
```

The request does not require CSRF. The server uses cookies to decide whether the
HTML contains authenticated preloaded data.

### Extracted Fields

| Data | Extraction | Notes |
|---|---|---|
| CSRF token | `<meta name="csrf-token" content="...">` | HTML entities must be decoded |
| Shared session key | `<meta name="shared_session_key" content="...">` | Used for cross-origin MessageBus polling |
| Turnstile sitekey | `data-sitekey="..."` | Useful for browser challenge flows |
| Base URI | `<meta name="discourse-base-uri" content="...">` | Empty or `/` means no prefix |
| CDN data | `#data-discourse-setup` attributes | `data-cdn`, `data-s3-cdn`, `data-s3-base-url` |
| Preloaded data | `data-preloaded="..."` | Decode HTML entities, then decode JSON |

## 4. Preloaded Data

The `data-preloaded` payload is an encoded JSON map. Some values are themselves
JSON-encoded strings; clients should normalize both direct objects and nested
JSON strings.

Common keys:

| Key | Purpose |
|---|---|
| `currentUser` | Authenticated user object |
| `siteSettings` | Feature gates, composer limits, plugin settings |
| `site` | Categories, tags, post action types, group/flair metadata |
| `topicList`, `topic_list`, `latest` | Initial topic list candidates |
| `topicTrackingStateMeta` | MessageBus channel initial ids |
| `topicTrackingStates` | Existing topic tracking states |
| `customEmoji` | Custom emoji list |
| `enabledReactions` | Reaction names, or derive from site settings |

Important `siteSettings` fields:

| Field | Use |
|---|---|
| `min_topic_title_length` | Topic title validation |
| `min_personal_message_title_length` | Private-message title validation |
| `min_post_length` | Reply body validation |
| `min_first_post_length` | Topic first-post validation |
| `min_personal_message_post_length` | Private-message body validation |
| `discourse_reactions_enabled_reactions` | Pipe-separated reaction names |
| `long_polling_base_url` | Alternate MessageBus origin |
| `secure_uploads` | Upload URL display/resolution policy |

## 5. Session Decision

Recommended session decision matrix:

| Bootstrap / probe result | Meaning | Recommended action |
|---|---|---|
| `currentUser` exists in bootstrap | Cookies are valid enough for startup | Use the user object and refresh in background if needed |
| No `currentUser`, no `_t` cookie | Anonymous session | Continue logged out |
| No `currentUser`, `_t` + `_forum_session` cookies exist | Recovering authenticated session | Preserve local cookies, enter the app, and refresh bootstrap/current user in background |
| No `currentUser`, only one identity cookie exists | Ambiguous | Preserve local cookies and offer login/challenge flow |
| Probe returns `current_user` | Authenticated | Use returned user |
| Probe returns `404`, `not_logged_in`, or no `current_user` | Invalid session | Treat as expired only in an explicit verification path; avoid destructive clearing from a failed startup gate |
| Probe fails due to network/Cloudflare/timeout | Inconclusive | Preserve local session and retry later |

Do not clear a user session based only on `BAD CSRF`, ordinary permission
errors, Cloudflare HTML, or transient network failures.

## 6. Site Metadata Fallback

```http
GET /site.json
```

Fetch this when bootstrap lacks required category/tag/composer metadata.

Useful fields:

- `categories`
- `top_tags`
- `can_tag_topics`
- `post_action_types`
- group and flair metadata
- `system_user_avatar_template`

## 7. MessageBus Startup

Use bootstrap data to configure MessageBus:

| Bootstrap data | MessageBus use |
|---|---|
| `siteSettings.long_polling_base_url` | Alternate polling base URL |
| `shared_session_key` | `X-Shared-Session-Key` header for alternate origin |
| `topicTrackingStateMeta` | Initial channel/message-id map |
| `currentUser.id` | Notification channels |

Typical initial subscriptions:

- Topic tracking channels advertised by `topicTrackingStateMeta`
- `/notification/{user_id}`
- `/notification-alert/{user_id}`
- Active topic channels only after a topic detail view is opened

## 8. Startup Request Inventory

| Order | Request | Required | Trigger |
|---:|---|---:|---|
| 1 | `GET /` | Yes | Startup bootstrap |
| 2 | `GET /session/current.json` | Optional | Explicit verification after startup or recovery from ambiguous cookie state |
| 3 | `GET /site.json` | Conditional | Missing site metadata |
| 4 | `POST /message-bus/{client_id}/poll` | Conditional | Authenticated or tracking-capable session with subscriptions |
| 5 | `GET /u/{username}.json` | Optional | Profile refresh or user page |
| 6 | `GET /notifications` | Optional | Notification list screen |

## 9. Error Handling

- Bootstrap HTML network failure should not erase cookies.
- Startup verification failure should surface a login/challenge path and preserve
  local session state instead of trapping the user in a deterministic retry loop.
- Cloudflare challenge HTML should be routed to the WebView challenge flow
  defined in [discourse-cloudflare-challenge-guide.md](discourse-cloudflare-challenge-guide.md).
- CSRF extraction failure can be recovered by `GET /session/csrf`.
- Malformed `data-preloaded` should degrade to explicit JSON API requests.
- MessageBus errors should use retry/backoff and should not block ordinary page loading.

## 10. Implementation Boundaries

The following choices are intentionally outside this protocol guide:

- Local database schema and migration order
- UI lifecycle and render tree construction
- State-management libraries
- Background task APIs
- Concrete cookie-store implementation
- Logging, tracing, and diagnostics sinks
