# iOS 16 UIKit Root Contract

**Status:** Started
**Goal:** Move Fire's production iOS surface to iOS 16-compatible UIKit/Texture
runtime ownership while keeping Rust as the only product logic engine.

## Scope

This plan starts the larger SwiftUI retirement effort with a narrow first PR:

- Lower the iOS app, widget extension, tests, and UniFFI cross-build defaults to
  iOS 16.
- Remove iOS 17-only SwiftUI APIs from shared host code that still compiles in
  production targets.
- Update architecture guardrails so future work cannot drift back to an iOS 17
  or SwiftUI-root assumption.
- Document the migration order for the larger UIKit root and screen work.

It intentionally does not rewrite every SwiftUI screen in the first PR. The
current repository still has transitional SwiftUI production views, and deleting
them safely depends on replacing the app root/navigation shell first.

## Architecture Contract

- UIKit + Texture is the production iOS runtime.
- iOS 16 is the minimum supported app, widget, and test deployment target.
- SwiftUI is allowed only for WidgetKit, Developer Tools, and explicitly tracked
  transitional bridges during migration.
- AppKit support must reuse the same Rust snapshot and command contracts as
  UIKit; it must not add a parallel product-logic path.
- Rust continues to own session, API orchestration, pagination/cache semantics,
  rich-text semantics, MessageBus, networking, and logging.

## Workstreams

### 1. Root Shell

Replace the SwiftUI `FireTabRoot` ownership boundary with:

- `FireSceneDelegate`
- `FireRootCoordinator`
- `FireMainTabBarController`
- one `UINavigationController` per production tab
- UIKit-owned auth/preheat/login presentations

This workstream must land before broad screen migration, because route handling,
deep links, notification taps, APM route labels, and auth-state transitions all
currently converge in the SwiftUI root.

### 2. UIKit List Runtime

Promote the current `FireDiffableListController` from a SwiftUI
`UIViewControllerRepresentable` bridge into the primary UIKit list runtime.
Migrate high-traffic list surfaces first:

- Home
- Notifications
- Search
- Messages
- Bookmarks (landed: `FireBookmarksViewController` on `FireListViewController`; Profile keeps only a thin SwiftUI-to-UIKit host until Profile itself migrates)
- Read history (landed: `FireReadHistoryViewController` on `FireListViewController`; Profile keeps only a thin SwiftUI-to-UIKit host until Profile itself migrates)
- Drafts

Each migrated screen should delete its previous production SwiftUI page instead
of leaving a fallback.

### 3. Auth and Composer

Move WebView login, onboarding, Cloudflare foreground challenge presentation,
and composer/editor flows onto UIKit. These surfaces own platform UI, text
input, WebKit, files, media pickers, and native presentation chrome while Rust
keeps session and API orchestration.

### 4. Profile and Secondary Surfaces

Migrate profile, badges, LDC/CDK, invite links, categories, and other secondary
production views after the root/list runtime is stable. Developer Tools can
remain SwiftUI until the production path is complete.

## Verification

- `scripts/verify-roadmap-architecture-constraints.sh`
- `rg 'deploymentTarget: "17\.0"|IPHONEOS_DEPLOYMENT_TARGET.*17\.0' native/ios-app`
- `rg 'sensoryFeedback|\.onChange\(of:.*\) \{ _,' native/ios-app/App -g '*.swift'`
- iOS build with `CODE_SIGNING_ALLOWED=NO`

## Follow-Up PRs

1. `codex/ios-uikit-root-shell`
2. `codex/ios-uikit-list-runtime`
3. `codex/ios-uikit-auth-composer`
4. `codex/ios-uikit-profile-secondary`
