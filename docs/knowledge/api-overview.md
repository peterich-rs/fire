# LinuxDo Discourse API Knowledge Base

This knowledge base describes observed backend protocol behavior for clients that
integrate with the LinuxDo Discourse deployment and its adjacent LinuxDo
services. It is intended to be reusable across client implementations and does
not assume any specific UI framework, language runtime, networking library, or
storage layer.

## Scope

The protocol surface is split into these groups:

| Group | Base URL | Purpose |
|---|---|---|
| Discourse main site | `https://linux.do` | Forum pages, JSON APIs, session cookies, CSRF, uploads, MessageBus |
| LDC Credit | `https://credit.linux.do` | LDC OAuth and credit reward APIs |
| CDK | `https://cdk.linux.do` | CDK OAuth and user-info APIs |
| Sticker market | Configurable static origin | Optional sticker pack JSON assets |

Client-owned services such as app update checks are not part of the LinuxDo
forum protocol. If a product needs update checks, document that product-specific
service outside the backend protocol reference.

## Core Conventions

- Discourse JSON endpoints usually accept and return JSON, while most mutating
  Discourse form actions use `application/x-www-form-urlencoded`.
- File uploads use `multipart/form-data` with `upload_type=composer`,
  `synchronous=true`, and a `file` part.
- Authenticated requests depend on the browser-issued Discourse cookies,
  primarily `_t` and `_forum_session`.
- Mutating Discourse requests require `X-CSRF-Token`; the token can be read from
  bootstrap HTML or fetched from `GET /session/csrf`.
- `discourse-logged-out`, `not_logged_in`, `BAD CSRF`, `Retry-After`, and
  Cloudflare challenge responses are protocol signals. How a client stores
  session state, retries, or displays errors is an implementation choice.
- MessageBus is an HTTP long-polling protocol under
  `/message-bus/{client_id}/poll`; it is separate from ordinary request/response
  APIs and may use an alternate long-polling origin advertised by bootstrap
  HTML.

## Module Index

| Module | Document | Covers |
|---|---|---|
| Global conventions | [api/01-global-conventions.md](api/01-global-conventions.md) | Base URLs, headers, cookies, content types, status signals |
| Auth and session | [api/02-auth-and-session.md](api/02-auth-and-session.md) | Current session, logout, CSRF, conservative session validation |
| WebView password login | [discourse-webview-login-guide.md](discourse-webview-login-guide.md) | Native form, minimal WebView JS login, hCaptcha, 2FA, login finalization |
| Cloudflare challenge | [discourse-cloudflare-challenge-guide.md](discourse-cloudflare-challenge-guide.md) | 403/429 detection, manual verification, request freeze, fresh cookie sync |
| Cookie/session state | [discourse-cookie-session-state-guide.md](discourse-cookie-session-state-guide.md) | Canonical cookies, freshness, priming, sentinel sweep, self-healing |
| Topics | [api/03-topics.md](api/03-topics.md) | Topic lists, detail, post batches, creation, topic state |
| Posts | [api/04-posts.md](api/04-posts.md) | Replies, edits, actions, reactions, flags, solutions, clicks |
| Users | [api/05-users.md](api/05-users.md) | Profiles, summaries, activity, follows, messages, badges, invites |
| Search | [api/06-search.md](api/06-search.md) | Full-text search, AI search, tags, mentions, recent searches |
| Notifications | [api/07-notifications.md](api/07-notifications.md) | Notification listing and read state |
| Uploads | [api/08-file-upload.md](api/08-file-upload.md) | Composer uploads and upload short-URL resolution |
| Polls and voting | [api/09-polls.md](api/09-polls.md) | Poll votes and topic voting plugin endpoints |
| Presence, categories, bookmarks, drafts | [api/10-presence-and-categories.md](api/10-presence-and-categories.md) | Read timings, presence, site metadata, category notifications, bookmarks, drafts |
| Extended features | [api/11-extended-features.md](api/11-extended-features.md) | Templates, nested views, policy plugin, emoji, Boost |
| MessageBus | [api/12-messagebus.md](api/12-messagebus.md) | Long polling, payload shape, message parsing, retries |
| LDC/CDK OAuth | [api/13-ldc-cdk-oauth.md](api/13-ldc-cdk-oauth.md) | OAuth login/callback/logout/user-info and LDC reward |
| Optional external assets | [api/14-misc-apis.md](api/14-misc-apis.md) | Sticker market assets and bootstrap call ordering |

## Common Flows

### Bootstrap

1. `GET /` to fetch the Discourse HTML shell.
2. Extract CSRF, current-user data, site settings, site metadata, preloaded topic
   list, topic tracking state, MessageBus shared session key, and optional
   long-polling origin from the HTML.
3. If no current user is present in bootstrap data but session cookies exist,
   call `GET /session/current.json` to validate the session.
4. Fetch `GET /site.json` when category, tag, or composer capability metadata
   is missing from bootstrap data.

### Login

1. Present a native username/password form.
2. Ensure a usable Cloudflare clearance exists; if absent, run manual WebView
   verification first.
3. Open the minimal same-origin WebView login document.
4. Let the WebView perform `GET /session/csrf`, hCaptcha create, and
   `POST /session.json`.
5. Classify the raw session response through shared session logic.
6. Extract login cookies from the live WebView before disposal.
7. Finalize login by applying trusted cookies, refreshing bootstrap with a
   bounded timeout, and notifying login-ready.

### Topic Detail

1. `GET /t/{topic_id}.json` or `GET /t/{topic_id}/{post_number}.json` loads
   topic metadata, an initial post batch, and `post_stream.stream`.
2. Load additional raw posts with
   `GET /t/{topic_id}/posts.json?post_ids[]=...` using IDs from
   `post_stream.stream`, or anchor around a post number with
   `post_number` and `asc`.
3. Sidecar APIs such as read timings, presence, AI summary, polls, reactions,
   and MessageBus updates should be treated as incremental capabilities around
   the authoritative topic/post payloads.

### Publish

1. Optionally save a composer draft with `POST /drafts.json`.
2. Upload files with `POST /uploads.json` and insert the returned `short_url`
   into Markdown.
3. Optionally validate mentions with `GET /composer/mentions`.
4. Create a topic or reply with `POST /posts.json`.
5. Delete the consumed draft with `DELETE /drafts/{draft_key}.json`.
