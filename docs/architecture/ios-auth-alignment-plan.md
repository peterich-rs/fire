# Align iOS Auth Session Recovery With Fluxdo

This document is now only a historical umbrella note for the earlier iOS auth/session alignment work. It is no longer the main entry for the current auth/session defect set.

## Still Relevant

- Rust owns session state, epoch advancement, login invalidation classification, and authenticated request execution.
- iOS owns `WKWebView` login, platform cookie extraction and mirroring, Cloudflare challenge completion, and native presentation policy.
- Stale-response invalidation remains a separate guard from current-response auth mutation handling.

## Current Entry Points

- Non-authoritative auth-cookie deletion on an otherwise successful response: [ios-auth-cookie-invalidation-fix.md](ios-auth-cookie-invalidation-fix.md)
- Partial auth rotation and authenticated-write host resync: [ios-auth-cookie-rotation-recovery-plan.md](ios-auth-cookie-rotation-recovery-plan.md)

## Historical Note

- This file originally grouped stale-response invalidation, cookie mirroring, and Cloudflare recovery under one plan.
- After the auth/session work split into smaller fixes, keeping detailed follow-up guidance here became duplicative and easy to misread as current policy.
- Keep using [fire-native-workspace.md](fire-native-workspace.md) for the long-lived ownership split; use the two narrower docs above for incident-specific guidance.
