# Fix iOS Auth Cookie Invalidation

This document is now a narrow historical note for the older false-positive logout bug. It does not cover the later partial auth rotation incident; use [ios-auth-cookie-rotation-recovery-plan.md](ios-auth-cookie-rotation-recovery-plan.md) for that route.

## Scope

- Problem shape: a successful response deleted `_t` or `_forum_session`, and the shared layer treated that deletion itself as authoritative logout evidence.
- This document does not cover successful responses that rotate part of the auth context while leaving the session temporarily mixed.

## Final Rule

- `discourse-logged-out` and `error_type: "not_logged_in"` remain the strong login invalidation signals.
- A `200` response that only sends `Set-Cookie: _t=; Max-Age=0` or `Set-Cookie: _forum_session=; Max-Age=0` is diagnostic only; Fire keeps local login state until stronger evidence arrives.
- Stale-response epoch protection remains separate and unchanged.
- Host-applied full cookie replacement can still change auth state; this fix only narrows network `Set-Cookie` deletion semantics.

## Why It Still Matters

- It removed a false-positive logout class without hiding the wire evidence in diagnostics.
- It created the boundary for the later auth rotation work: after this fix, the remaining bug was no longer “logged out too early”, but “kept a mixed auth generation alive for the next write”.
