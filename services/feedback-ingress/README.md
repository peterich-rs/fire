# Fire Feedback Ingress

Cloudflare Worker that accepts in-app feedback submissions and opens a GitHub
issue on behalf of the user. **GitHub credentials never ship in the mobile app.**

## Why this exists

Fire clients cannot safely hold a GitHub write token. Anyone who extracts the
binary would get unlimited issue spam and write access. This Worker is the only
component that holds a GitHub App installation token or fine-grained PAT.

## Flow

```text
App (native UI)
  → Rust export_feedback_bundle (redacted session + logs)
  → POST multipart to this Worker
  → Worker rate-limits, stores attachments, creates GitHub Issue
```

## Setup

1. Create a GitHub App (preferred) or fine-grained PAT scoped to issues write on
   the target repo (public `peterich-rs/fire` and/or a private triage repo).
2. Optional: create an R2 bucket for attachment storage.
3. Configure secrets:

```bash
cd services/feedback-ingress
npx wrangler secret put GITHUB_TOKEN          # or use GitHub App secrets below
npx wrangler secret put GITHUB_APP_ID         # optional GitHub App path
npx wrangler secret put GITHUB_APP_PRIVATE_KEY
npx wrangler secret put GITHUB_INSTALLATION_ID
```

4. Edit `wrangler.toml` for account, route, and `GITHUB_OWNER` / `GITHUB_REPO`.
5. Deploy:

```bash
npx wrangler deploy
```

## API

### `POST /v1/feedback`

`multipart/form-data` fields:

| Field | Required | Description |
| --- | --- | --- |
| `title` | yes | Issue title (max 120 chars) |
| `body` | yes | Description / repro steps |
| `category` | no | `bug` / `crash` / `performance` / `ui` / `suggestion` / `other` |
| `severity` | no | `critical` / `high` / `medium` / `low` |
| `platform` | no | `ios` / `android` |
| `app_version` | no | Marketing version |
| `build_number` | no | Build number |
| `username` | no | LinuxDo username if logged in |
| `diagnostic_session_id` | no | From Rust diagnostics |
| `bundle` | no | Redacted feedback JSON from `export_feedback_bundle` |
| `media` | no | One or more image/video parts (size-capped) |

Response `201`:

```json
{
  "ok": true,
  "issue_number": 123,
  "issue_url": "https://github.com/peterich-rs/fire/issues/123"
}
```

## Security notes

- Never put `GITHUB_TOKEN` in the app binary or client config files.
- Rate-limit by IP (and later install id).
- Reject oversized payloads.
- Feedback bundles must be the **redacted** export only.
- Prefer a private triage repo or private R2 URLs if logs may contain usernames/URLs you do not want public.

## Status

Scaffold for TF feedback pipeline. Wire app submit path after deploy + secrets.
