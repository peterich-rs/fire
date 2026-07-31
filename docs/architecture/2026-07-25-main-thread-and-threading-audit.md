# Main-thread / background threading audit (iOS)

Date: 2026-07-25  
Scope: Fire iOS host (`native/ios-app`), with Rust/UniFFI ownership notes.

## Goal

- Main thread: UI only (view hierarchy, gesture, Texture layout application, snapshot apply).
- Background: parsing, measurement, merge/dedup, render-cache build, FFI-adjacent transforms.
- Rust: protocol orchestration, tree presentation, list models, session authority — keep expanding this surface instead of growing Swift business logic.

## Already in good shape

| Area | Pattern |
|------|---------|
| Topic cooked → render cache | `FireTopicPresentation.detailRenderCache` via `Task.detached` in `FireTopicDetailStore` |
| Post cell layout height | `FirePostLayoutManager` background queue + main publication |
| Topic detail feed snapshot items | `FireTopicDetailSnapshotAssembler.buildSnapshot` in `Task.detached` from VC |
| Topic tree / page fetch | Rust `fetchTopicDetailPage` returns `sourceSnapshot` + `treePresentation` |
| Home topic rows | Mostly Rust-generated row models; host formats timestamps |
| UniFFI session/network | `async` boundary; not blocking UI runloop with sync FFI |
| Texture node-block UIKit | Hardened 2026-07-25: no `.view`/layer in off-main configure |

## Residual main-thread work (by severity)

### P1 — completed / remaining

1. **`FireTopicDetailStore` page apply** ✅  
   `prepareTopicDetailPagePayload` runs tree dedupe + detail synthesis + post lookup in `Task.detached`; main only commits maps and kicks render.

2. **Cooked display-segment IR** ✅ (2026-07-25 follow-up)  
   Rust `fire_rich_text::display_segments` + UniFFI `displaySegmentsFromRenderDocument` owns image/text segment splitting.  
   Swift deleted `rawRenderSegments` / container walk; host only maps rich mini-docs → `NSAttributedString` and images → cells.  
   Checksum no longer uses `String(reflecting:)`.

3. **Home feed dirty-row token rebuild** ✅  
   `FireHomeFeedStore.prepareTopicRowsMerge` snapshots indexes then merges + rebuilds content tokens in `Task.detached`.  
   Main only assigns `topicRows` / tokens / visibility. Single-row `patchTopicCounts` stays sync (cheap).

### P2 — acceptable on main for now

| Area | Why OK |
|------|--------|
| Diffable / Texture snapshot apply | Must be main; keep diffs small via content tokens |
| Captcha sheet detent animation | UIKit sheet API is main-only; height measure is JS → main debounced |
| Quick-reply / toolbar chrome | Thin UIKit |
| Login form / onboarding | UI-bound |
| Keychain credential load | Short; already in async prepareLoginForm |

### P3 — watch / measure

- `FireDiffableListController` large `reconfigureItems` batches during scroll idle.
- Message-bus fan-in onto MainActor stores (debounce already present for some paths).
- Image decode is generally off main; keep UIImage assignment on main only.

## Threading rules (host)

1. **Texture `nodeBlock` / `configure`:** node properties only. Any `UIView` / `CALayer` / gesture attach → `didLoad` or `performOnMain`.
2. **Never** `DispatchQueue.main.sync` from Texture workers (deadlock risk).
3. **Pure transforms** (`unique*`, merge posts, synthesize detail, render cache) → `nonisolated` / `Task.detached` / dedicated queue.
4. **Rust owns** pagination cursors, tree presentation, missing-post windows, session classification — do not reimplement in Swift “for convenience”.
5. **Main actor stores** may *orchestrate* async work but should not *compute* large collections inline.

## Concrete changes

### Pass 1
- `FireTopicDetailStore.applyTopicDetailPagePayload` off-main prepare.

### Pass 2
- **Home feed:** `mergeTopicRows` + content-token rebuild are `nonisolated static`; list load/apply paths await `prepareTopicRowsMerge` on a detached task.
- **Cooked IR:** Rust `RenderDisplaySegment` + `display_segments`; UniFFI export; Swift presentation uses it and drops the old segment walker.
- **Sendable indexes:** `FireEntityIndex` / `FireOrderedIDList` require `Sendable` entity/id.

## Suggested follow-ups (ordered)

1. Instrument detached prepare ms vs main commit ms for topic detail + home feed.
2. Split remaining `FireTopicDetailStore` pure helpers into a Sendable reducer module.
3. Further thin Swift attributed-string builder once Android shares the same display-segment IR.
4. Optional: main-thread hang detector in DEBUG (os_signpost / MetricKit) behind developer tools.

## Related fixes (same day)

- Off-main UIKit in `FirePostCellNode` (hang root cause during topic open).
- Captcha sheet height debounce / phase-1 hide on challenge open.
- Login loading: button spinner only (no dim overlay).

## Follow-up: Texture color appearance (dark-mode body/username)

- Dynamic colors bound into `ASTextNode` must not rely on the Texture display-queue trait environment.
- Capture `UITraitCollection` on the main thread (loaded collection view / window override) and bake with `FireTextureAttributedText.resolvingDynamicColors`.
- Theme preference changes must call a host refresh path (`refreshColorAppearance`); updating only `window.overrideUserInterfaceStyle` is insufficient for Texture bitmaps.
- Keep pure transforms (render-cache HTML → attributed string) off-main; resolve-for-Texture stays at bind time on the UI path.
