# Home Feed Filter Chrome Design

Date: 2026-07-26  
Status: iOS revised — leading parent drawer + home category-arrow subcategory sheet; Android parity pending  
Scope: iOS home first; Android should share the same state model and panel IA

## Problem

Current home chrome stacks three always-visible filter rows:

1. parent-category chips (`全部 / 未分类 / 开发调优 / …`)
2. list-kind chips (`最新 / 最新发布 / 未读 / 未看 / 热门 / 精华`)
3. tag entry (`+ 标签`)

User feedback and the current UI both point at the same gaps:

- too much vertical chrome before the first topic
- parent categories are hard to scan in a long horizontal strip
- subcategories are effectively second-class (sheet + `Menu`)
- category / kind / tag compete at equal visual weight even though they are different jobs

## Goals

1. Make “what am I browsing?” readable in one glance.
2. Make parent + child category selection first-class.
3. Keep list content as the primary surface.
4. Reuse the existing home scope pipeline (`kind + categoryId + tags`) instead of inventing a parallel filter path.
5. Keep one authoritative interaction model on iOS and Android.

## Non-goals

- Left-edge drawer as the iOS primary entry
- Multi-category multi-select
- Replacing Discourse list kinds
- Pixel-matching web or Fluxdo
- Building a second filtered-list stack beside `FireHomeFeedStore`

## Design summary

> Leading drawer picks parent category / 全部 only.  
> Home status bar shows current scope; category arrow opens subcategory sheet when children exist.  
> Kind stays a lightweight menu on the status bar.

```text
Before                         After
------                         -----
[cat chips............]        [ 开发调优 / Rust ▾ ]  [最新 ▾]  [#tag ×]
[kind chips...........]        [ 全部 | Rust | 前端 | 更多 ]   // only when parent has children
[+ 标签]                       [ topic rows ... ]
[topic rows...]
```

## Information architecture

| Layer | Surface | Role |
|---|---|---|
| L0 | Scope status bar | Always visible current category path, kind, selected tags |
| L1 | Subcategory shortcut strip | Only when selected parent has children |
| L2 | Scope panel | Full parent list + children + search + tags |
| L3 | Kind menu | Lightweight menu from the kind capsule |

### Why not a left drawer as default

A left drawer is a reasonable container for parent categories, but:

- iOS edge gestures fight interactive pop / system back affordances
- discovery is weaker than an explicit status capsule
- it encourages platform-split shells

Preferred container:

- **iOS:** sheet / half-screen panel from the category capsule
- **Android:** same panel IA; optional navigation-drawer shell later, same view-model

## Wireframes

### 1) Default home

```text
┌──────────────────────────────────────┐
│ 首页                          ✎  🔍   │
├──────────────────────────────────────┤
│ [ 全部 ▾ ]              [ 最新 ▾ ]   │  ← L0 status bar
├──────────────────────────────────────┤
│ topic                                │
│ topic                                │
│ topic                                │
└──────────────────────────────────────┘
```

Notes:

- no subcategory strip
- no tag row
- kind is secondary, not a full chip runway

### 2) Parent selected, has children

```text
┌──────────────────────────────────────┐
│ 首页                          ✎  🔍   │
├──────────────────────────────────────┤
│ [ 开发调优 ▾ ]          [ 最新 ▾ ]   │
│ [全部] [Rust] [前端] [求职] [更多]    │  ← L1 shortcut strip
├──────────────────────────────────────┤
│ topic                                │
└──────────────────────────────────────┘
```

Rules:

- `全部` means the parent category itself
- selecting a child updates the status capsule to `开发调优 / Rust`
- `更多` opens the full panel focused on that parent

### 3) Child + tags selected

```text
┌──────────────────────────────────────┐
│ [ 开发调优 / Rust ▾ ] [最新▾] [#rust×]│
│ [全部] [Rust✓] [前端] [求职] [更多]    │
├──────────────────────────────────────┤
│ topic                                │
└──────────────────────────────────────┘
```

Rules:

- selected tags appear only when non-empty
- tag chip delete removes one tag
- long-press / trailing clear on category capsule clears category path (and optionally tags)

### 4) Scope panel (L2)

```text
┌──────────────────────────────────────┐
│ 选择范围                      完成    │
│ [ 搜索分类或标签...               ]  │
├──────────────┬───────────────────────┤
│ 全部          │ 开发调优              │
│ 未分类        │ ----------------------│
│ 开发调优  ✓   │ ○ 全部 开发调优        │
│ 国产替代      │ ● Rust                │
│ 资源聚合      │ ○ 前端                │
│ 运营反馈      │ ○ 求职                │
│ ...           │                       │
│              │ 热门标签               │
│              │ #rust  #swift  #ai     │
└──────────────┴───────────────────────┘
```

Interaction:

1. Left pane lists parents + synthetic `全部`
2. Right pane lists:
   - parent-as-all row
   - children of the highlighted parent
   - optional hot tags for the current scope
3. Search filters parents/children/tags in one list
4. Selection applies immediately and refreshes home scope
5. Panel may auto-dismiss on category pick; tag toggles can keep it open

### 5) Kind menu

```text
[最新 ▾]
  • 最新
    最新发布
    未读
    未看
    热门
    精华
```

Keep current `TopicListKindState.orderedCases`; only change presentation.

## State model

### Existing store fields to keep

From `FireHomeFeedStore`:

```text
selectedTopicKind: TopicListKindState
selectedHomeCategoryId: UInt64?
selectedHomeTags: [String]
allCategories: [FireTopicCategoryPresentation]
topTags: [String]
```

Existing query assembly already supports child categories via:

- `categoryId`
- `categorySlug`
- `parentCategorySlug` derived from `parentCategoryId`

So **subcategory filtering is mostly a UI/IA gap**, not a backend-protocol gap.

### Presentation model to add (UI-facing, derived)

```swift
struct FireHomeScopePresentation: Equatable {
    var kind: TopicListKindState
    var categoryID: UInt64?
    var tags: [String]

    /// `nil` = 全部
    var selectedCategory: FireTopicCategoryPresentation?
    /// If selected is a child, this is its parent; if selected is parent, equal to selected.
    var selectedParent: FireTopicCategoryPresentation?
    var selectedChild: FireTopicCategoryPresentation?
    var categoryPathTitle: String           // "全部" | "开发调优" | "开发调优 / Rust"
    var kindTitle: String                   // localized kind label
    var childShortcuts: [FireHomeChildShortcut]
    var showsChildShortcutStrip: Bool
}

struct FireHomeChildShortcut: Equatable, Identifiable {
    var id: UInt64?                        // nil = parent-all
    var title: String
    var isSelected: Bool
}
```

Derivation rules:

```text
selectedHomeCategoryId == nil
  -> path "全部"
  -> no child strip

selected is parent P
  -> path P.name
  -> child strip = [全部(P), ...children(P)] if children non-empty
  -> selected shortcut = 全部(P)

selected is child C of parent P
  -> path "P.name / C.name"
  -> child strip for P
  -> selected shortcut = C
```

### Panel view state

```swift
struct FireHomeScopePanelState: Equatable {
    var searchText: String
    var highlightedParentID: UInt64?       // left-pane highlight; nil = 全部
    var selectedCategoryID: UInt64?        // committed home scope
    var selectedTags: [String]
    var recentParentIDs: [UInt64]          // local-only, max ~6
}
```

Notes:

- `highlightedParentID` can differ from committed selection while browsing the panel
- committing still goes through store methods, not a second source of truth

### Store API shape

Keep mutations centralized on `FireHomeFeedStore`:

```text
selectTopicKind(kind)
selectHomeCategory(categoryId)
addHomeTag / removeHomeTag / clearHomeTags
```

Add thin helpers (no new network concepts):

```text
clearHomeCategory()                        // select nil
selectHomeParent(parentId)                 // select parent id
selectHomeChild(childId)                   // select child id
clearHomeScopeFilters()                    // category nil + tags []
scopePresentation() -> FireHomeScopePresentation
children(of parentId) -> [Category]
parents() -> [Category]
```

Optional local persistence later:

```text
recentParentCategoryIDs: [UInt64]          // UserDefaults / app prefs
```

Do **not** move kind/category/tags ownership into the view controller.

## UI composition

### iOS

Replace in `FireHomeView` / home collection header:

| Remove / demote | Replacement |
|---|---|
| `FireHomeCategoryTabsCell` always-on runway | `FireHomeScopeStatusBar` |
| `FireHomeFeedSelectorCell` full chip row | kind capsule + menu |
| always-on `FireHomeTagChipsCell` | selected-tag chips in status bar; picker inside panel |
| `FireCategoryBrowserSheet` grid + menu | `FireHomeScopePanelController` dual-pane |

Suggested ownership:

```text
FireHomeViewController
  ├─ FireHomeScopeStatusBarView          // L0
  ├─ FireHomeChildShortcutBarView        // L1 conditional
  ├─ topic list...
  └─ presents FireHomeScopePanelController
```

Implementation preference:

- pure UIKit for status/shortcut/panel (home is already UIKit-first)
- retire SwiftUI category browser shell for this path once panel lands
- one authoritative panel path; no SwiftUI fallback

### Android

Mirror the same L0/L1/L2 model with Jetpack UI, sharing labels and selection rules.  
A drawer shell is optional and must bind the same scope state.

## Behavior details

### Selection

- Choosing a category commits immediately and triggers existing debounced refresh (`scheduleDebouncedRefresh`)
- Choosing a category currently clears tags (`selectHomeCategory` already does this) — **keep** that unless product later wants sticky tags
- Kind changes do not clear category/tags
- Tag add/remove keep category

### Status bar

- Category capsule opens scope panel
- Kind capsule opens kind menu
- Tag chips are removable
- If filters are non-default, show a subtle clear affordance

### Child shortcut strip

- Appears only when committed parent has children
- Horizontal, compact, single line
- Does not replace the panel for deep browsing

### Search in panel

Priority match order:

1. parent title
2. child title
3. tag

Empty search shows hierarchy; non-empty search shows flat grouped results.

### Empty / error

Reuse current home empty/error surfaces.  
When scope is narrow and empty, CTA options:

- 查看大类全部
- 清除筛选

### Accessibility

- category color is decoration only
- selected rows expose traits / checkmarks
- status capsules need labels like `分类：开发调优 / Rust`、`排序：最新`
- child strip is a selectable tab-like control group

## Mapping to current code

### Already good

| Piece | Location | Notes |
|---|---|---|
| scope fields | `FireHomeFeedStore` | kind/category/tags already authoritative |
| rust home scope sync | `setCurrentHomeTopicListScope` | keep |
| child category query | `parentCategorySlug` derivation in `loadTopics` | already works if child id selected |
| category metadata | bootstrap `allCategories` + `parentCategoryId` | enough for dual-pane |
| kind enum | `TopicListKindState` | reuse labels |

### Needs UI rewrite

| Piece | Change |
|---|---|
| `FireHomeCategoryTabsCell` | replace with status bar + optional child strip |
| `FireHomeFeedSelectorCell` | demote to menu |
| `FireHomeTagChipsCell` | only selected tags / move picker into panel |
| `FireCategoryBrowserSheet` | replace with dual-pane panel |
| home snapshot sections | drop always-on 3 filter sections; add status/shortcut items |

### Needs small store/presentation additions

| Piece | Change |
|---|---|
| `FireHomeScopePresentation` | pure derivation helper |
| recent parents | optional local prefs |
| clear helpers | convenience wrappers over existing selects |

### Likely unchanged

- `TopicListQueryState` shape
- MessageBus incremental refresh rules
- topic row rendering
- composer initial category/tags handoff from current scope

## Implementation plan

### P0 — structure and subcategory parity

1. [x] Add `FireHomeScopePresentation` derivation + unit tests.
2. [x] Build `FireHomeScopeStatusBarCell` and wire kind menu.
3. [x] Build `FireHomeScopePanelController` dual-pane with parent/child selection.
4. [x] Remove always-visible category/kind/tag chip runways from home snapshot.
5. [x] Ensure selecting a child category uses existing `selectHomeCategory(childId)` path end-to-end.
6. [x] Update iOS README + this doc status when landed.
7. [x] Conditional child shortcut strip (pulled forward from P1 for usable subcategory access).

### P1 — shortcuts and polish

1. Child shortcut strip after parent selection.
2. Selected tag chips in status bar.
3. Panel search.
4. Clear-scope affordance + empty-scope CTAs.
5. Recent parent ordering.

### P2 — platform parity / optional shells

1. Android same IA.
2. Optional Android drawer container around the same panel state.
3. Only if needed: iOS navbar `line.3.horizontal` opens the **same** panel (not a second hierarchy).

## Test plan

### Unit

- path title:
  - nil -> `全部`
  - parent -> parent name
  - child -> `parent / child`
- child shortcuts:
  - none when no children
  - includes parent-all + children
  - selected states
- query regression:
  - child selection still produces `categoryId=child` + `parentCategorySlug=parent`

### UI / manual

1. Default home shows one status row only.
2. Open panel, select parent with children, strip appears.
3. Select child from strip and from panel; both same result.
4. Long category names truncate in capsule; panel shows full names.
5. Kind menu changes only kind.
6. Tags selectable from panel; removable from status bar.
7. Changing category clears tags (current behavior).
8. Dynamic type / small phone: status bar wraps or compresses without covering topic rows incorrectly.

## Open product choices

Defaults below are recommended if not overridden:

1. **Panel dismiss:** auto-dismiss on category commit; stay open for tag toggles.  
2. **Sticky tags across category changes:** no.  
3. **Remember last scope across launches:** yes for kind + category; tags optional later.  
4. **Synthetic “未分类”:** keep if bootstrap/API already exposes it as a real category; do not special-case a fake chip runway.

## Decision

Accepted direction:

- **No iOS-primary left drawer**
- **Yes dual-pane category panel**
- **Yes single status bar as the standing chrome**
- **Yes conditional subcategory shortcuts**
- **Reuse `FireHomeFeedStore` scope, do not fork feed filtering**
