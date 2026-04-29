# iOS Quality & Polish Orchestration Plan

**Goal:** Execute Tracks A, B, and C from `docs/superpowers/specs/ios-quality-and-polish-design.md` as auditable subagent-owned slices, landing phase-sized commits on one working branch and opening a single PR only after the full quality/polish pass is complete.

**Scope:** This document governs execution order, ownership, audit artifacts, commit granularity, and handoff rules for:

- `docs/superpowers/plans/2026-04-26-ios-track-a-test-layer-slimming.md`
- `docs/superpowers/plans/2026-04-26-ios-track-b-tab-startup-preload.md`
- `docs/superpowers/plans/2026-04-26-ios-track-c-app-wide-animation-polish.md`

When a track plan's older commit/push/PR wording conflicts with this orchestration doc, this document wins.

## Track order

1. **Track A** — test layer slimming.
2. **Track B** — tab startup preload.
3. **Track C / Phase 1** — FireMotion foundation.
4. **Track C / Phases 2-4** — T1, T2, T3 polish slices after Phase 1 is available in the working branch.

Track A must land first because it rewrites the iOS test lane, CI invocation, and generated Xcode project output used by the later tracks. Track B and Track C both touch app-root coordination plus regenerated project artifacts, so they should run sequentially unless the active worker is prepared to rebase and fully revalidate.

## Required subagent roles

Every non-trivial slice follows the same role sequence. Use the role names in the subagent descriptions even if the runtime resolves them to the default agent implementation.

1. **Explore** — locate the owning files, nearby tests, generated artifacts, and doc surfaces.
2. **Analyze** — confirm the controlling code path, interface expectations, validation target, and conflict surface.
3. **Patch** — make the planned code/doc changes for that slice only.
4. **Runner** — run the narrowest build/test/manual verification needed to falsify the slice.
5. **Review** — inspect diff shape, formatting, doc sync, and residual risks before handoff.

Parallel read-only exploration is allowed. Parallel writes are only allowed when file sets do not overlap. If two slices touch the same file, serialize Patch/Runner/Review.

## `manage_todo_list` policy

`manage_todo_list` is the authoritative progress tracker for the overall workstream.

- Create one top-level todo item per execution slice.
- For this workstream, the default slices are: Track A, Track B, Track C Phase 1, Track C Phase 2, Track C Phase 3, Track C Phase 4, unified review/PR.
- Markdown checkboxes inside the track plans are execution notes only; do not treat them as the source of truth for progress.
- Update the todo list whenever a slice starts, finishes, or is blocked.

## Required artifact bundle

Every subagent handoff must give the main agent enough evidence to continue without reopening broad analysis.

Required contents:

- touched-file list
- concise diff summary
- commands run, with success/failure outcome
- build/test/manual validation notes
- docs updated or checked
- remaining risks, blockers, or user decisions needed
- proposed commit message, or the commit SHA if VCS ownership was explicitly assigned to that slice

If a validation step is unavailable, the handoff must say so explicitly.

## Commit policy

Commit at phase granularity only.

- **Track A:** one commit
- **Track B:** one commit
- **Track C:** one commit per phase

Do not create task-level or micro-fix commits unless a failed validation forces a localized repair. If the active subagent does not own VCS operations, it returns the artifact bundle plus the proposed commit message and stops.

## PR policy

- Do not open separate PRs for Track A, Track B, or any Track C phase.
- After all slices are complete and revalidated together, the main agent opens **one unified PR** covering the full quality/polish pass.
- The unified PR summary should stay grouped by Track A / Track B / Track C phase outcomes rather than by file inventory.

## User-confirmation gates

If a slice encounters a public-interface change, multiple materially different implementation choices, or data/rollback risk, pause and ask the user through `vscode_askQuestions` before proceeding.

The same rule applies when the plan intentionally leaves an in-scope spec item unresolved. Record the question, the recommended option, and the impact of the choice in the artifact bundle.

## Final handoff

Once all slices are done, the main agent performs the unified review, prepares the final PR, and uses `vscode_askQuestions` as the only follow-up channel for post-task confirmation and next-step selection.