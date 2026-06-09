# Internal Testing Evidence

This file records manual App Store Connect, Play Console, release-candidate
upload, tester invite, and feedback-triage evidence. Keep the related P4 gates
open until every required row is complete and linked from
`release-gate-evidence.md`.

## Required Evidence

| Date | Platform | Gate | Owner | Status | Evidence Link | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |

## Required Rows

Record one row for each gate below:

- `iOS` / `App Store Connect record`
- `Android` / `Play Console record`
- `iOS` / `Internal testing build`
- `Android` / `Internal testing build`
- `iOS` / `Tester invites`
- `Android` / `Tester invites`
- `iOS` / `Feedback triage`
- `Android` / `Feedback triage`

## Evidence Rules

- Record each required platform/gate pair exactly once; duplicate rows are
  rejected so the release evidence remains unambiguous.
- `Date` must be a real calendar date in `YYYY-MM-DD` form.
- `Status` must be `Complete` or `Accepted`.
- `Owner`, `Evidence Link`, and `Notes` must identify real release evidence;
  fake, mock, placeholder, dummy, synthetic, TODO/TBD, `example.com`,
  `not-real`, or `not real` markers are rejected.
- `Evidence Link` may point to store-console exports, screenshots, build
  metadata, tester group records, or feedback triage notes. Use a well-formed
  HTTP(S) URL with a hostname or a safe repo-relative path to a non-empty local
  file; placeholder hosts such as localhost, `.local`, `.test`, and `.invalid`
  are rejected.
- Internal testing build notes must include a build number and 7-40 character
  commit SHA.
- Tester invite notes must include group/list name and invite date.
- Feedback triage notes must summarize numeric blocker count, accepted risks,
  and links to any release-blocking issues, or state `none` when no blocking
  issues remain.
- `Accepted` rows require approval/waiver context and a reason, risk, or
  exception in `Notes`; use a clear shape such as
  `Approved by <owner>; reason: <decision>`.
