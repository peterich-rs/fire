# MessageBus 长轮询 API

Discourse MessageBus uses HTTP long polling. Clients subscribe by sending a form body whose keys are channel names and whose values are the last message id seen for each channel.

## 1. Poll

```http
POST /message-bus/{client_id}/poll
Content-Type: application/x-www-form-urlencoded
```

`client_id` is a stable random id for the running client session. The same id is also used by upload and presence APIs.

### Base URL

Most deployments poll the main Discourse origin. LinuxDo bootstrap HTML can also advertise an alternate long-polling origin and a `shared_session_key`.

When polling a different origin:

```http
X-Shared-Session-Key: <shared_session_key>
```

In that mode, the shared-session header can replace ordinary same-origin cookies for the polling request.

### Request Headers

```http
Accept: text/plain, */*; q=0.01
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
Dont-Chunk: true
X-SILENCE-LOGGER: true
```

`Discourse-Background: true` is only sent for background polling mode.

CSRF is not required for MessageBus polling.

### Request Body

```text
/latest=6855147&/new=104155&/__status=0&/topic/123=5678
```

Each key is a channel. Each value is the last `message_id` already processed for that channel. Use `-1` for a new subscription when no initial id is known.

### Response

The response is streamed text. Message chunks are separated by `|`; each chunk is a JSON array:

```text
[{"channel":"/latest","message_id":6855148,"data":{}}]|[{"channel":"/new","message_id":104156,"data":{}}]|
```

Message object:

```json
{
  "channel": "/latest",
  "message_id": 6855148,
  "data": {}
}
```

Clients should parse complete chunks only after the `|` delimiter and update the stored last message id per channel after a message is accepted.

## 2. Channel Inventory

Channels are dynamic and depend on bootstrap data, logged-in user id, visible topic, enabled plugins, and presence state.

Common channels:

| Channel | Purpose |
|---|---|
| `/__status` | Server status message containing latest ids for channels |
| `/latest` | Latest topic list updates |
| `/new` | New-topic tracking |
| `/unread` | Unread-topic tracking |
| `/topic/{topic_id}` | Topic post and topic-state events |
| `/topic/{topic_id}/reactions` | Discourse reactions updates for a topic |
| `/presence/discourse-presence/reply/{topic_id}` | Presence updates for the reply channel |
| `/notification/{user_id}` | Notification list updates |
| `/notification-alert/{user_id}` | Notification alert/count updates |

Bootstrap HTML can include topic-tracking channel metadata and initial message ids. Clients should subscribe to those channels exactly as advertised instead of hard-coding only `/latest`, `/new`, or `/unread`.

## 3. Topic Payload Types

`/topic/{topic_id}` messages use `data.type` or equivalent payload fields to describe the change. Observed payload categories include:

| Type | Meaning | Typical client action |
|---|---|---|
| `created` | A post was created | Fetch or insert the new post payload |
| `revised` | A post was edited | Refresh the affected post |
| `rebaked` | Cooked HTML was regenerated | Refresh cooked content |
| `deleted` | A post was deleted | Mark/remove affected post |
| `stats` | Topic/post counters changed | Refresh counters |
| `boost_added` | Boost plugin payload changed | Refresh boost state |
| `policy_change` | Policy plugin state changed | Refresh policy data |
| `reload_topic` | Topic should be reloaded | Re-fetch topic detail/list data |
| `notification_level_change` | Current user's topic notification level changed | Update topic notification state |

Payload shape varies by type. Clients should preserve unknown fields and handle unknown types by invalidating or refreshing the affected topic rather than ignoring the message permanently.

## 4. Topic Tracking Payloads

Topic-tracking channels carry `message_type` values such as:

- `new_topic`
- `unread`
- `read`
- `dismiss_new`
- `dismiss_new_posts`

Payloads commonly contain `topic_id`, `highest_post_number`, `last_read_post_number`, `notification_level`, `category_id`, and topic id arrays for dismiss operations. Some payloads omit fields that can be inferred from existing local state; clients should merge payload fields into the previous tracking state rather than replacing the whole state blindly.

## 5. Presence Handoff

`GET /presence/get?channels[]=/discourse-presence/reply/{topic_id}` returns a keyed object with `message_id`. To continue updates over MessageBus, subscribe to:

```text
/presence/discourse-presence/reply/{topic_id}
```

with the returned `message_id` as the last seen id.

## 6. Retry Policy

Recommended behavior:

- Read timeout is normal for long polling; immediately start the next poll.
- On `429`, honor `Retry-After` and add jitter before retrying.
- On transient network errors, retry with exponential backoff capped around 30 seconds.
- When the subscription set changes, cancel or finish the current poll and start a new poll with the updated channel map.
- In background mode, increase the delay between polls to reduce battery and server load.
