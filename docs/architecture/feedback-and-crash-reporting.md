# Feedback and Crash Reporting

Status: design + foundation in progress (TF public beta).

## Product goals

1. Testers and users can submit **反馈与建议** from the app without a GitHub account.
2. Submissions become **GitHub Issues** for maintainer triage.
3. Optional diagnostics (xlog / redacted session / network traces) can be attached with explicit consent.
4. Automatic crash telemetry (Crashlytics / similar) is a **separate** track from narrative feedback.

## Non-goals

- Shipping a GitHub PAT or App private key inside the mobile binary.
- Using Discourse `uploads.json` for feedback media.
- Replacing TestFlight / Play Console feedback channels (those remain secondary).
- Treating email as the primary support channel.

## Architecture

```text
Native feedback UI
  → UniFFI FireDiagnosticsHandle.export_feedback_bundle(...)
  → Rust redacted package on disk
  → (future) openwire POST multipart to feedback ingress
  → Cloudflare Worker holds GitHub secret
  → GitHub Issues API (bot-created issue)
```

### Ownership

| Concern | Owner |
| --- | --- |
| Form UI, media pickers, consent | Native iOS / Android |
| Redacted package assembly, flush logs | Rust `fire-core` diagnostics |
| GitHub issue creation token | Cloudflare Worker secrets only |
| Crash symbol upload / free-rate | Platform crash SDK (optional Phase B) |

### Client API surface (Rust)

| API | Leaves device? | Session cookies | Sensitive headers |
| --- | --- | --- | --- |
| `export_support_bundle` | Local share / developer tools only | Full (intentional for local debug) | Present |
| `export_feedback_bundle` | Yes (feedback upload / share) | Redacted only | Redacted to `[redacted]` |

Feedback package path:

- `diagnostics/feedback-bundles/fire-feedback-{ts}.json`
- Payload fields: `kind: "feedback"`, `session_redacted: true`, host meta, capped log windows, capped network traces

UniFFI:

- `FireDiagnosticsHandle.export_feedback_bundle(host_context)`

### Ingress

Scaffold: `services/feedback-ingress/`

- `POST /v1/feedback` multipart
- Rate limit, size caps, create GitHub issue with labels `feedback`, `beta`, platform, category
- Optional R2 for attachment blobs
- Secrets: `GITHUB_TOKEN` or GitHub App installation credentials

**Never** call `api.github.com` with a write credential from the app.

## UI placement

Preferred product entry (iOS):

1. **我的（Profile 一级）→ 反馈与建议** — first row in the account card for early-beta discoverability
2. **摇一摇** / login-screen icon for pre-login and stuck flows
3. Presentation is a **full-screen secondary page** (same stack as bookmarks/settings), not a sheet panel

Developer Tools remain under Settings for full-fidelity local export only.

## Users without GitHub

Users do not need GitHub. The Worker bot creates the issue. Fallback “在浏览器打开 Issues” remains for power users who already have GitHub.

Email is not the primary path: no shared triage board, weak attachment policy, spam, and no labels/PR linkage. Optional maintainer notify email can mirror the issue, not replace it.

## Crash reporting (Firebase / etc.)

| Signal | Mechanism |
| --- | --- |
| User story + repro + screenshots | In-app feedback |
| Unhandled crash stacks / ANR | Crashlytics (or Sentry) — optional |
| Local iOS APM ZIP | Already exists (PLCrashReporter + MetricKit); opt-in attach only |

Android already depends on Firebase for FCM; Crashlytics can reuse the same Firebase project. iOS would add the Crashlytics SDK + dSYM upload.

Enabling automatic crash upload is a **privacy / store questionnaire change**. Current privacy copy states Fire does not automatically upload crash/diagnostics. Update privacy policy and data-safety forms before shipping Crashlytics.

Recommended sequencing:

1. Ship feedback form + redacted bundle + Worker issues (this design).
2. Add Crashlytics if TF crash volume justifies it.
3. Link Crashlytics ids into feedback when both exist.

## Privacy constraints

Must never leave the device toward GitHub / public issues:

- `_t`, `_forum_session`, `cf_clearance`, CSRF tokens
- Full non-redacted `export_session_json`
- Raw Cookie / Set-Cookie / Authorization headers in network traces

Safe with consent:

- LinuxDo username / user id (optional)
- App version, build, platform, diagnostic session id
- Redacted session + capped log tails + redacted traces
- User-selected screenshots / short video

Public vs private issues:

- Public repo issue bodies are world-readable.
- Prefer private triage repo **or** private R2 attachment URLs for logs/media; keep public issue text non-sensitive.

## Implementation checklist

- [x] `export_feedback_bundle` (Rust) with redaction tests
- [x] UniFFI `export_feedback_bundle`
- [x] Worker scaffold under `services/feedback-ingress/`
- [x] iOS Settings → 反馈与建议 form (+ 摇一摇 + 登录页入口)
- [x] Android Profile → 反馈 form
- [x] Submit via system share sheet (report text + redacted JSON)
- [ ] Deploy Worker + GitHub secret + labels
- [ ] Rust submit path (openwire to ingress, no Discourse cookies)
- [ ] Wire share → Worker auto GitHub issue
- [ ] Privacy / store doc updates when upload is enabled
- [ ] Optional Crashlytics
- [ ] Android shake-to-feedback (optional parity)

## Related paths

- `rust/crates/fire-core/src/diagnostics.rs`
- `rust/crates/fire-uniffi-diagnostics/`
- `services/feedback-ingress/`
- `docs/release/test-feedback-template.md`
- `docs/release/privacy-policy.md`
- `docs/release/public-urls.md`
