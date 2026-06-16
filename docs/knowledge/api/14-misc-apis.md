# Bootstrap HTML、可选外部资产与调用顺序

This document covers protocol-adjacent surfaces that are useful for reproducing a LinuxDo client but are not ordinary Discourse JSON endpoints.

## 1. Discourse Bootstrap HTML

```http
GET https://linux.do/
Accept: text/html
```

The Discourse HTML shell contains metadata and preloaded JSON that can avoid several startup requests.

### Extracted Metadata

| Data | Source | Use |
|---|---|---|
| CSRF token | `<meta name="csrf-token" content="...">` | `X-CSRF-Token` for mutating requests |
| Shared session key | `<meta name="shared_session_key" content="...">` | `X-Shared-Session-Key` for cross-origin MessageBus polling |
| Turnstile sitekey | `data-sitekey="..."` | Cloudflare challenge page integration |
| Base URI | `<meta name="discourse-base-uri" content="...">` | Sub-path deployment prefix |
| CDN URLs | `#data-discourse-setup` attributes such as `data-cdn`, `data-s3-cdn`, `data-s3-base-url` | Static assets and upload URL resolution |
| Preloaded JSON | `data-preloaded="..."` | Startup data blocks |

HTML attribute values can contain HTML entities. Decode entities before parsing embedded JSON.

### Preloaded Data Blocks

Common blocks:

| Key | Meaning |
|---|---|
| `currentUser` | Current authenticated user, when cookies are valid |
| `siteSettings` | Site settings, plugin flags, composer limits, `long_polling_base_url` |
| `site` | Categories, top tags, `can_tag_topics`, `post_action_types`, group/flair metadata |
| `topicList` / `topic_list` / `latest` | Initial topic list; deployments can vary key names |
| `topicTrackingStateMeta` | MessageBus channel initial ids for topic tracking |
| `topicTrackingStates` | Existing per-topic tracking state |
| `customEmoji` | Custom emoji metadata |
| `enabledReactions` or site-setting derived reactions | Available reaction names |

Important `siteSettings` fields for composers and feature gates include:

| Field | Meaning |
|---|---|
| `min_topic_title_length` | Minimum topic title length |
| `min_personal_message_title_length` | Minimum private-message title length |
| `min_post_length` | Minimum reply length |
| `min_first_post_length` | Minimum first-post length |
| `min_personal_message_post_length` | Minimum private-message body length |
| `discourse_reactions_enabled_reactions` | Pipe-separated enabled reaction names |
| `long_polling_base_url` | Optional alternate MessageBus polling origin |
| `secure_uploads` | Whether upload short links should remain protected |

## 2. Optional Sticker Market Assets

Sticker market data is an optional static JSON integration. The base URL is product-configurable; do not hard-code it into the LinuxDo protocol layer.

Observed path shape:

```http
GET {sticker_market_base_url}/assets/market/index/index.json
GET {sticker_market_base_url}/assets/market/index/page-{page}.json
GET {sticker_market_base_url}/assets/market/group-{group_id}.json
```

Clients should cache these static JSON responses and may use stale cache data if the asset host is unavailable. Cache storage and expiration policy are implementation choices.

## 3. Recommended Startup Order

1. Restore cookies for `https://linux.do`.
2. `GET /` and parse bootstrap metadata/preloaded data.
3. If bootstrap contains `currentUser`, treat it as an authenticated user hint.
4. If cookies exist but bootstrap has no `currentUser`, validate with `GET /session/current.json`.
5. Load `GET /site.json` only for missing category/tag/composer metadata.
6. Configure MessageBus with `long_polling_base_url` and `shared_session_key` if present.
7. Subscribe to advertised topic-tracking channels and any active user/topic channels.

## 4. Recommended Login Order

1. Ensure a usable Cloudflare clearance exists, running manual verification if
   needed.
2. Open the minimal same-origin WebView login document.
3. Let WebView perform login CSRF, hCaptcha create, and `/session.json`.
4. Classify the session response through shared session logic.
5. Extract trusted login cookies from the live WebView before disposal.
6. Finalize login with bounded bootstrap refresh.
7. Start MessageBus subscriptions after the user id and channel metadata are
   known.

## 5. Recommended Topic Detail Order

1. `GET /t/{topic_id}.json` or `GET /t/{topic_id}/{post_number}.json`.
2. Read `post_stream.stream` and keep the topic metadata from the detail payload.
3. Fetch missing post payloads with `GET /t/{topic_id}/posts.json?post_ids[]=...`.
4. Start sidecar capabilities as needed: `POST /topics/timings`, `GET /presence/get`, `POST /presence/update`, AI summary, reactions, polls, and topic MessageBus subscriptions.

## 6. Recommended Publish Order

1. Optionally save a draft with `POST /drafts.json`.
2. Upload files with `POST /uploads.json`.
3. Validate mentions with `GET /composer/mentions` when needed.
4. Create a topic, reply, or private message with `POST /posts.json`.
5. Remove the consumed draft with `DELETE /drafts/{draft_key}.json`.

## 7. Out-Of-Scope App Services

App update checks, release feeds, telemetry, crash reporting, product-specific CDNs, and local cache storage formats are application infrastructure. They should not be documented as LinuxDo backend protocol unless the service is part of LinuxDo itself.
