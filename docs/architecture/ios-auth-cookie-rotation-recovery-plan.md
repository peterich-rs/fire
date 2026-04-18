# Repair Partial Auth Rotation Before Authenticated Writes

This is the main document for the auth/session incident captured in `fire-support-1776481517964.json`. It covers the newer partial auth rotation path and the authenticated-write host resync route. The older false-positive cookie deletion fix remains separately scoped in [ios-auth-cookie-invalidation-fix.md](ios-auth-cookie-invalidation-fix.md).

## Incident Summary

- `GET /t/1992131.json?track_visit=true` succeeded while still using the old `_forum_session` and old `_t`.
- The same response rotated `_forum_session`, but did not provide a new `_t` or a new CSRF token.
- The shared session accepted that patch as ordinary steady state.
- The next authenticated write, often `POST /topics/timings`, reused stale write credentials and then hit strong invalidation.
- The topic detail reset was downstream of that logout path, not the primary defect.

## Landed Route

### Shared Rust semantics

- Any auth-key change `(_t, _forum_session)` now counts as an auth-context change, regardless of whether it came from platform sync or network `Set-Cookie`.
- Auth-context change advances the shared session epoch.
- If the same mutation did not also install a fresh CSRF token, Fire clears the stale CSRF token immediately.
- Strong logout still only comes from explicit server evidence such as `discourse-logged-out` or `error_type: "not_logged_in"`.
- A partial network rotation records a runtime-only auth recovery hint so later writes can distinguish this case from explicit logout and from the older cookie deletion bug.

### Authenticated-write recovery

- The read response that observed the rotation is still allowed to complete; repair is deferred to the next authenticated write.
- `FireSessionStore` owns a single authenticated-write preflight instead of special-casing `/topics/timings`.
- Preflight order is:
  1. refresh CSRF if needed
  2. if the same auth epoch still carries a recovery hint, run one host cookie resync
  3. apply the refreshed platform cookies through the shared session store
  4. refresh CSRF again, then execute the original write
- Host resync is single-flight and at most once per auth epoch.
- Late resync results from an older epoch are dropped.
- If CSRF refresh already surfaces `LoginRequired`, host resync is bypassed and the existing strong invalidation path wins.

### Boundaries

- Do not force logout only because one auth cookie rotated.
- Do not trigger WebKit cookie reads from the read path that observed the rotation.
- Do not make `/topics/timings` a one-off fix; every authenticated write should benefit from the same preflight.
- Keep the recovery hint runtime-only rather than persisting it into `SessionSnapshot`.

## Why This Is The Primary Entry

- It captures both landed pieces from the recent work: shared auth rotation tracking and iOS host resync.
- It preserves the key design choice that `FireSessionStore`, not `FireAppViewModel` or `FireWebViewLoginCoordinator`, owns write-time recovery policy.
- It matches the added regression coverage for partial auth rotation, CSRF clearing, one-shot host resync, and stale epoch dropping.