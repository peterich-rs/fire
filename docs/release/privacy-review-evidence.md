# Privacy Review Evidence

This file records maintainer/legal review evidence for release privacy,
data-safety, backup, diagnostics, and license materials. Keep the
`Maintainer/legal privacy review` P4 gate open until every required row is
complete and linked from `release-gate-evidence.md`.

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
- `Date` must be a real calendar date in `YYYY-MM-DD` form.
- `Status` must be `Complete` or `Accepted`.
- `Reviewer` must identify the maintainer, legal reviewer, or explicit
  approver for the row. Reviewer, evidence-link, and notes metadata must not
  contain fake, mock, placeholder, dummy, synthetic, TODO/TBD, `example.com`,
  `not-real`, or `not real` markers.
- `Evidence Link` may point to signed review notes, issue approvals, checklist
  exports, generated inventories, or repository files with reviewer comments.
  Use a well-formed HTTP(S) URL with a hostname or a safe repo-relative path to a
  non-empty local file; placeholder hosts such as localhost, `.local`, `.test`,
  and `.invalid` are rejected.
- `Accepted` rows require approval/waiver context and a waiver reason, risk, or
  exception in `Notes`; use a clear shape such as
  `Approved by <reviewer>; reason: <decision>`.
- `Final publication approval` notes must mention approval to publish, release,
  or submit the privacy policy and store-console answers for the release
  candidate.
