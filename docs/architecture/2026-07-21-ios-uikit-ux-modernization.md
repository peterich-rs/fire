# iOS UIKit-First UX Modernization

## Goal

Improve perceived polish (visual consistency, micro-interactions, loading chrome) without rewriting the app stack. Product UI is UIKit-first; topic-detail posts remain Texture-only.

## Unified dark design language (2026-07-21)

Reference style (consumer iOS dark settings / profile cards) is adopted **app-wide**, not only Profile/Settings:

- **Canvas:** pure black in dark / OLED (`FireTheme.uiCanvas`)
- **Cards / grouped rows:** elevated charcoal (`uiSurface` ~`#1C1C1E`, `uiSurfaceSecondary` ~`#2C2C2E`)
- **Icon language:** monochrome SF Symbols on dark wells; brand accent remains Fire orange
- **Chrome:** nav/tab use theme canvas + material via `FireTheme.applyGlobalAppearances()`
- **Profile / Settings:** closer visual replica of the reference (section labels, capsule appearance control, independent sign-out card, footer version)

Shared helpers live in `App/Core/UIKit/FireUIKitDesignLanguage.swift`.

## Constraints

1. Prefer mature open-source libraries over hand-rolled animation/toast/skeleton engines.
2. Prefer UIKit over SwiftUI for product surfaces.
3. Do not reintroduce SwiftUI post-row fallbacks in topic detail.
4. Cap new UI SPM packages; always access them through Fire facades.

## Dependencies (UI chrome)

| Package | Version | Facade |
|---------|---------|--------|
| Juanpe/SkeletonView | 1.31.0 | `FireUIKitSkeleton` |
| BastiaanJansen/toast-swift | 2.1.3 | `FireUIKitToast` |
| SnapKit | 5.7.1 | used by shared empty/error views |
| Texture / Nuke / JXPhotoBrowser | existing | unchanged hard-problem stack |

System APIs remain authoritative for: `UIRefreshControl`, `UIVisualEffectView` / bar appearances, `UISheetPresentationController`, haptics (`FireMotionHaptics`), and diffable list animations.

## Design tokens

`FireTheme` exposes:

- `ui*` `UIColor` accessors for UIKit
- matching SwiftUI `Color` wrappers from the same adaptive factories (including OLED)

`FireTopicListPalette` is a temporary compatibility forwarder to `FireTheme.ui*`.

## Motion

- Tokens: `FireMotionTokens`
- UIKit helpers: `FireMotionUIKit`
- Haptics: `FireMotionHaptics`
- SwiftUI modifiers remain for residual SwiftUI screens only

## Migration order

1. Theme + toast + skeleton facades on existing UIKit lists — **done**
2. Filtered topic list → ListKit UIKit VC (`FireFilteredTopicListViewController`) — **done**
3. Profile tab + public profile → UIKit VCs (`FireProfileViewController`, `FirePublicProfileViewController`) — **done**
4. Topic detail chrome polish (nav material, theme colors, reaction haptics; Texture cells untouched) — **done**
5. Residual SwiftUI cleanup + docs — **in progress / progressive**

### Residual SwiftUI (allowed)

- Widgets extension
- Developer tools
- Secondary profile destinations still pushed as hosts: badges, LDC/CDK, invites, follow lists, activity timeline, settings
- Temporary composer/editor sheets
- Category browser sheet shell (filtered list content is UIKit)

## Explicit non-goals

- Full SwiftUI rewrite or full Texture rewrite of all lists
- Cross-platform pixel animation parity with Android
- MJRefresh-class pull-to-refresh libraries
- Custom navigation transition engines when system interactive pop is sufficient
