# Release Materials

This directory contains release-preparation source material for Fire.

## Documents

- `app-store-description.md` - App Store listing draft
- `play-store-description.md` - Play Store listing draft
- `privacy-policy.md` - privacy policy draft aligned to current code
- `app-store-data-collection.md` - App Store privacy questionnaire draft
- `play-store-data-safety.md` - Play Store Data Safety draft
- `privacy-review-evidence.md` - maintainer/legal review evidence log
- `testflight-setup.md` - TestFlight setup guide
- `play-store-testing-setup.md` - Play Store internal/closed testing guide
- `internal-testing-evidence.md` - App Store / Play Store testing evidence log
- `test-feedback-template.md` - tester feedback template
- `performance-benchmarks.md` - release benchmark targets and log
- `accessibility-audit-checklist.md` - release accessibility checklist
- `release-gate-evidence.md` - manual P4 gate evidence register
- `third-party-licenses.md` - generated third-party dependency inventory

## Store Marketing Assets

Final screenshots and graphics live under `native/ios-app/marketing/` and
`native/android-app/marketing/`. After release-candidate media is captured, run:

```bash
scripts/verify-marketing-assets.sh
```

The verifier is expected to fail while those folders contain only placeholders.
Passing validation is required before marking the store-media evidence rows
complete, but it is not a substitute for release-candidate capture and review.
Final asset filenames must not contain fake, mock, placeholder, dummy,
synthetic, TODO/TBD, `example.com`, `not-real`, or `not real` markers.
Screenshot dimensions must decode cleanly and be at least 320px on each side;
PNG screenshots must contain more than a single flat color; the Play feature
graphic must be PNG content with exact `1024x500` dimensions and non-flat pixel
content. If an App Preview is included, `app-preview.mp4` must contain MP4
`ftyp` content.

## Performance Evidence

Release benchmark results are recorded in `performance-benchmarks.md`. After
physical-device release measurements are added, run:

```bash
scripts/verify-performance-benchmarks.sh
```

The verifier is expected to fail while the results log is empty, while any iOS
or Android target metric is missing, or while threshold failures lack an
accepted disposition with explicit approval/waiver context, such as
`Approved by ...; reason: ...`, in `Notes`. Result values must include numeric
units such as seconds, milliseconds, fps plus janky-frame percentage, or MB/GB;
memory rows with multiple values must label the peak value with `peak`, such as
`peak 190 MB` or `190 MB peak`; if multiple peak values are labelled, the
verifier compares the highest labelled peak. Device, build type, result, and
notes metadata must not contain fake/mock/placeholder markers or placeholder URL
hosts such as localhost, `.local`, `.test`, and `.invalid`. Dates must be real
calendar dates in `YYYY-MM-DD` form. Rows with missing or extra Markdown table
columns are rejected; keep the exact table shape and escape literal `|`
characters in cell text.

## Accessibility Evidence

Release accessibility results are recorded in
`accessibility-audit-checklist.md`. After physical-device release-candidate
audits are added, run:

```bash
scripts/verify-accessibility-audit.sh
```

The verifier is expected to fail while the results log is empty, while any
required screen or audit category lacks iOS/Android coverage, or while blocking
failures lack an accepted disposition with approval/waiver context and a reason
in `Notes`, for example `Approved by ...; reason: ...`. Dates must be real
calendar dates in `YYYY-MM-DD` form. Tester, device, and notes metadata must not
contain fake/mock/placeholder markers or placeholder URL hosts such as localhost,
`.local`, `.test`, and `.invalid`. Rows with missing or extra Markdown table
columns are rejected; keep the exact table shape and escape literal `|`
characters in cell text.

## Internal Testing Evidence

Store records, release-candidate uploads, tester invites, and feedback triage
are recorded in `internal-testing-evidence.md`. After store-console actions and
tester triage are complete, run:

```bash
scripts/verify-internal-testing-evidence.sh
```

The verifier is expected to fail while required iOS or Android testing-track
evidence rows are missing, duplicated, or incomplete. `Accepted` rows require
approval/waiver context and a reason in `Notes`, for example
`Approved by ...; reason: ...`. Evidence links must be well-formed HTTP(S) URLs
with hostnames or safe repo-relative paths to non-empty local files; directories
do not satisfy local evidence links. Placeholder hosts such as localhost,
`.local`, `.test`, and `.invalid` are rejected, as are malformed hosts with empty
labels or labels that start or end with `-`. Owner, evidence-link, and notes
metadata must not contain fake/mock/placeholder markers.
Dates must be real calendar dates in `YYYY-MM-DD` form. Rows with missing or
extra Markdown table columns are rejected; keep the exact table shape and escape
literal `|` characters in cell text.

## Privacy Review Evidence

Maintainer/legal review evidence is recorded in `privacy-review-evidence.md`.
After review of privacy policy, store privacy answers, backup behavior,
diagnostic redaction, privacy manifests, and license inventory is complete, run:

```bash
scripts/verify-privacy-review-evidence.sh
```

The verifier is expected to fail while required review rows are missing,
duplicated, or incomplete. `Accepted` rows require approval/waiver context and a
waiver reason in `Notes`, for example `Approved by ...; reason: ...`. Evidence
links must be well-formed HTTP(S) URLs with hostnames or safe repo-relative paths
to non-empty local files; directories do not satisfy local evidence links.
Placeholder hosts such as localhost, `.local`, `.test`, and `.invalid` are
rejected, as are malformed hosts with empty labels or labels that start or end
with `-`. Reviewer, evidence-link, and notes metadata must not contain
fake/mock/placeholder markers. Dates must be real calendar dates in
`YYYY-MM-DD` form. Rows with missing or extra Markdown table columns are
rejected; keep the exact table shape and escape literal `|` characters in cell
text.

## Manual Release Inputs

Real screenshots, preview videos, store records, legal review, device performance numbers, and accessibility audit results are not generated by these docs. Record final evidence in `release-gate-evidence.md`; keep P4 roadmap acceptance unchecked until every required gate has completed evidence and the shared P4 evidence suite passes.

Before marking P4 acceptance complete, run the full release-readiness wrapper:

```bash
scripts/verify-release-readiness.sh
```

It runs the shared P4 release evidence suite, roadmap plan contract, roadmap
architecture constraints, roadmap implementation evidence, and roadmap P4
acceptance verifiers. It is expected to fail until all manual P4 evidence is
complete.

The shared non-recursive P4 evidence suite can also be checked directly:

```bash
scripts/verify-p4-release-evidence-suite.sh
```

It runs the store-media, performance, accessibility, internal-testing,
privacy-review, and release-gate evidence verifiers. For isolated regression
coverage without real manual evidence, run:

```bash
scripts/test-release-verifiers.sh
```

That script uses temporary fixtures only. It proves that the shared suite can
pass with complete fixture evidence, that the full release-readiness wrapper can
pass with complete fixture evidence, that both fail when lower-level fixture
evidence is missing, that fake-evidence markers, malformed store media,
flat PNG placeholders, non-measurement performance results, target misses marked
`Pass`, ambiguous or misleading multi-value memory results, duplicate manual
evidence rows, invalid calendar dates, placeholder metadata fields, dead local
evidence paths, malformed evidence URLs, malformed URL hosts, placeholder URL
hosts, extra Markdown table columns, missing Markdown table boundaries, and weak
accepted-waiver notes are rejected, and that checked P4 roadmap acceptance is
allowed only when the full fixture suite passes.

The final evidence register can also be checked directly:

```bash
scripts/verify-release-gates.sh
```

The evidence verifier is expected to fail while any evidence row is still
`Not started`, missing owner/link/date metadata, or out of sync with the exact
required gate set in `release-gate-evidence.md`. `Accepted` release-gate rows
must also include explicit waiver/approval language and a reason in `Notes`,
such as `Approved by ...; reason: ...`; vague status notes do not close a manual
gate. Evidence links must be well-formed HTTP(S) URLs with hostnames or safe
repo-relative paths to non-empty local files; directories do not satisfy local
evidence links. Placeholder hosts such as localhost, `.local`, `.test`, and
`.invalid` are rejected, as are malformed hosts with empty labels or labels that
start or end with `-`. Manual evidence verifiers also reject completed or
accepted rows whose owner, reviewer, tester, device, result, evidence-link, or
notes metadata still contain fake, mock, placeholder, dummy, synthetic, TODO/TBD,
`example.com`, `not-real`, or `not real` markers, whose dates are impossible
calendar dates, or whose rows have missing or extra Markdown table columns.

The roadmap acceptance boxes can also be checked directly:

```bash
scripts/verify-roadmap-p4-acceptance.sh
```

This verifier fails if the design document's P4 acceptance rows are renamed,
duplicated, or missing. If any P4 acceptance box is checked, it also requires
the shared non-recursive P4 evidence suite to pass: store marketing assets,
performance benchmarks, accessibility audit, internal testing evidence, privacy
review evidence, and release-gate evidence.

The roadmap document set can be checked directly:

```bash
scripts/verify-roadmap-plan-contract.sh
```

This verifier requires the one design spec and the four implementation plans to
stay present with the expected P1/P2/P3/P4 top-level task counts.

The roadmap architecture constraints can also be checked directly:

```bash
scripts/verify-roadmap-architecture-constraints.sh
```

This verifier checks the platform/Rust ownership boundary, current minimum API
targets, iOS topic-detail native runtime path, and reference/infrastructure
repository boundaries.

The checked P1-P3 roadmap acceptance claims can be checked directly:

```bash
scripts/verify-roadmap-implementation-evidence.sh
```

This verifier checks concrete code paths, files, and scoped cleanup patterns
that support the completed P1-P3 acceptance rows. It is not a substitute for
the manual P4 release evidence verifiers.
