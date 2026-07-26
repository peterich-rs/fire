# Privacy Review Evidence

This file records maintainer/legal review evidence for release privacy,
data-safety, backup, diagnostics, and license materials. Keep the
`Maintainer/legal privacy review` P4 gate open until every required row is
complete and linked from `release-gate-evidence.md`.

## Public hosting decision (TestFlight)

Until a dedicated site exists, store-facing privacy/support URLs point at the
public GitHub `main` branch. Canonical list:

- https://github.com/peterich-rs/fire/blob/main/docs/release/public-urls.md
- Privacy Policy: https://github.com/peterich-rs/fire/blob/main/docs/release/privacy-policy.md

These links satisfy the **HTTPS privacy policy URL** requirement for TestFlight
external testing when the repository is public. Full App Store legal sign-off
still belongs in the table below before treating P4 privacy gates as closed.

## Required Evidence

| Date | Review Area | Reviewer | Status | Evidence Link | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## Required Rows

Record one row for each review area below:

- `Privacy policy`
- `App Store privacy questionnaire`
- `Play Store Data Safety`
- `Android backup behavior`
- `Diagnostic export redaction`
- `iOS privacy manifests`
- `Third-party licenses`
- `Final publication approval`

## Evidence Rules

- Record each required review area exactly once; duplicate rows are rejected so
  the release evidence remains unambiguous.
- `Date` must be a real calendar date in `YYYY-MM-DD` form and must not be in
  the future.
- Rows with missing or extra Markdown table columns are rejected; keep the exact
  table shape and escape literal `|` characters in cell text.
- `Status` must be `Complete` or `Accepted`.
- `Reviewer` must identify the maintainer, legal reviewer, or explicit
  approver for the row. Reviewer, evidence-link, and notes metadata must not
  contain fake, mock, placeholder, dummy, synthetic, TODO/TBD, `example.com`,
  `not-real`, or `not real` markers.
- `Evidence Link` may point to signed review notes, issue approvals, checklist
  exports, generated inventories, or repository files with reviewer comments.
  Use a well-formed HTTP(S) URL with a fully qualified hostname or a safe
  repo-relative path to a non-empty local file; directories do not satisfy local
  evidence links. Single-label URL hosts, placeholder hosts such as localhost,
  `.local`, `.test`, and `.invalid`, and malformed hosts with empty labels or
  labels that start or end with `-` are rejected.
- `Accepted` rows require approval/waiver context and a waiver reason, risk, or
  exception in `Notes`; use a clear shape such as
  `Approved by <reviewer>; reason: <decision>`.
- `Final publication approval` notes must mention approval to publish, release,
  or submit the privacy policy and store-console answers for the release
  candidate.
