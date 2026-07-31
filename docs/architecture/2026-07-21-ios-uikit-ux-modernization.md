# iOS UIKit-First UX Modernization

## Goal

Improve perceived polish (visual consistency, micro-interactions, loading chrome) without rewriting the app stack. Product UI is UIKit-first; topic-detail posts remain Texture-only.

## Unified dark design language (2026-07-21)

Reference style (consumer iOS dark settings / profile cards) is adopted **app-wide**, not only Profile/Settings:

- **Canvas:** pure black in dark / OLED (`FireTheme.uiCanvas`)
- **Cards / grouped rows:** elevated charcoal (`uiSurface` ~`#1C1C1E`, `uiSurfaceSecondary` ~`#2C2C2E`)
- **Icon language:** colored rounded icon wells + white SF Symbols on profile/settings rows; brand accent remains Fire orange
- **Corners:** tighter continuous radii (`cornerRadius` 14 / `medium` 12 / `small` 10) — direct and clear, not overly bubbly
- **Chrome:** nav/tab use theme canvas + material via `FireTheme.applyGlobalAppearances()`
- **Profile / Settings:** reference-style cards with colored wells, compact top inset, capsule appearance control, independent sign-out card, footer version
- **Home topic rows:** metric chips stay muted by default; notable/high values lift color weight (likes use the same 3-tier ladder as replies — not more); view *surge* (young + high velocity) shows a static 🔥/🚀 badge **after the count** so icon→number spacing stays constant, plus a short finite pulse on the badge; high likes can emit a one-shot 2-heart balloon. Micro-animations only run after the list is **settled** (~220ms after scroll stop / first paint) and **once per topic ID per session** via `FireTopicListMetricEffectCoordinator` (scrolling back does not replay). Reduce Motion disables motion entirely.

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
   - Profile menu rows use `FireProfileMenuRowCell`: colored icon wells + white SF Symbols, 48pt single-line rows, trailing count left of chevron (e.g. `15条`)
   - Header sits tight under the nav bar; three equal stat columns (粉丝 / 获赞 / 关注) on a soft secondary strip
   - Follow / followers lists are UIKit (`FireFollowListViewController`) pushed on the secondary stack; user rows push `FirePublicProfileViewController` with a **stack-aware** topic presenter
   - Public profile **最近动态** uses `FireAppRouteControllerFactory.present` cascade (preferred presenter → live nav / secondary stack → root secondary). Never `_ = presenter.present` with the SwiftUI environment default `.local` (that only produced cell selection animation)
   - Route cascade logs via `ios.topic-route` (`route present cascade start/outcome=…`); missing `topic_id` on activity rows logs a warning
   - Residual SwiftUI `FireFollowListView` is a thin host of the UIKit controller (no `NavigationLink` profile drill-down)
4. Topic detail chrome polish (nav material, theme colors, reaction haptics; Texture cells untouched) — **done**
5. Topic detail quick-reply bar: WeChat-style opaque full-width bottom strip — **done**
   - **Pure UIKit** bar (`FireTopicQuickReplyBarView`) layered above Texture feed — not a Texture overlay
     (Texture compositing was still letting feed text show through the left side)
   - Solid opaque black chrome; resting pad = home indicator; keyboard pad = 8pt flush above keyboard
   - Keyboard lifts via bottom Auto Layout constraint; feed `contentInset.bottom = barHeight + keyboardOverlap`
   - Keyboard frame handling is synchronous on the posting thread (no `receive(on:)` hop) so swipe-to-reply keeps the bar locked to the keyboard animation; `presentQuickReplyInput()` commits bar geometry before `becomeFirstResponder()`
6. Residual SwiftUI cleanup + docs — **in progress / progressive**
7. Topic detail interaction polish — **done**
   - Shared press bounce: `UIControl.fireBindPressBounce` / `ASButtonNode.fireBindPressBounce` (`.button` / `.compact` / `.chip`) used on login, send, submit, empty-state, composer, feed chips, reactions, polls, etc.
   - Reaction chips: press bounce + optimistic local update with network rollback on failure; chips stay tappable while request is in-flight
   - Topic detail nav bar uses **opaque** canvas chrome so light-mode image content cannot bleed through as a black bar
   - Topic detail toolbar chrome: no generic `话题` title; real topic title pins centered after the in-feed header title scrolls away; trailing actions collapse inline into `...` once on first pin (teaching affordance), then stay compact + title stays pinned unless the user expands manually; manual expand auto-collapses after idle (`FireTopicDetailToolbarCoordinator`); titleView claims expanded/leftover width only (never content-sized), so long titles truncate instead of shoving the trailing icon capsule off-screen
   - Boost chips align with Fluxdo: compact continuous pills with leading **avatar + plain body only** (no bolt glyph, no `@username` text prefix); body still strips leading attribution from Rust `displayText`
   - Author metadata aligns with Fluxdo post header: primary line keeps staff role chips only; secondary line is `@username` + humanized `user_title` (e.g. `trust_lv_3` → `L3 活跃用户`) + status; primary group / flair names are not dumped as raw text chips
   - Topic-detail post density: tighter header/meta spacing; reply context (`回复 @user`) sits on the username row; `@handle`/title stay on the secondary row; reply-thread bubble toggle uses accent orange for both icon and count when expanded; OP has no cell overflow `...` (nav toolbar owns topic actions); reply bottom chrome keeps bubble + reactions + overflow `...` (toolbar-aligned horizontal fade expand, auto-collapse); reaction pills are compact (12pt emoji / 11pt count, 5pt gutters, 5pt wrap line gap; idle = clear/hairline, mine = soft accent; dark uses faint glass fill); left-swipe reveals reply
   - Collapsed post body: blank-line runs (`\n\n`) are normalized before ASTextNode truncation so empty lines no longer burn the 4-line budget / look like huge row gaps; collapsed height is measured with the same ASTextNode max-lines path
8. Topic detail Texture **color appearance** hardening — **done**
   - Root cause: `ASTextNode` async display can resolve dynamic `UIColor.label` / `uiCanvas` against the wrong `userInterfaceStyle` (often light), baking near-black glyphs onto the pure-black dark canvas — body and primary username disappear while mid-gray `@handle` / titles remain faintly visible. Runtime theme switch previously only flipped `window.overrideUserInterfaceStyle` + global chrome; post cells / render-bound attributed strings were not re-baked.
   - Fix: rich text + post meta use `FireTheme.uiInk` / `uiSubtleInk` (not bare system labels); `FireTextureAttributedText` resolves dynamic colors with an explicitly captured trait collection before binding to Texture; `FirePostCellRenderPayload.colorTraits` is captured on the main thread in the feed node-block; body/username ASTextNodes prefer sync display; `didEnterVisibleState` re-bakes from live hierarchy traits.
   - Appearance bus: `FireTopicDetailViewController` listens for `fireAppearancePreferenceDidChange` and `traitCollectionDidChange` → `feedController.refreshColorAppearance()` (visible post cells soft rebind + `reloadData` for one-shot factory nodes) and refreshes nav / quick-reply chrome.
   - Tests: `FireTextureAttributedTextTests` covers appearance tokens, light/dark ink bake, and truncation accent resolution.

### Residual SwiftUI (allowed)

- Widgets extension
- Developer tools
- Secondary profile destinations still pushed as hosts: badges, LDC/CDK, invites, activity timeline, settings
- Follow / followers lists are UIKit (`FireFollowListViewController`); residual SwiftUI only hosts that controller
- Temporary composer/editor sheets
- Category browser sheet shell (filtered list content is UIKit) — scheduled to be replaced by the UIKit home scope panel in `docs/architecture/2026-07-26-home-feed-filter-chrome-design.md`

### Next polish target

- Home feed filter chrome redesign: **iOS revised** — leading parent-category drawer + home status bar; category arrow opens subcategory sheet when children exist (`FireHomeCategoryDrawerController` / `FireHomeSubcategoryPanelController`). Remaining: recent parents, Android parity. Design: `docs/architecture/2026-07-26-home-feed-filter-chrome-design.md`.

## Explicit non-goals

- Full SwiftUI rewrite or full Texture rewrite of all lists
- Cross-platform pixel animation parity with Android
- MJRefresh-class pull-to-refresh libraries
- Custom navigation transition engines when system interactive pop is sufficient
