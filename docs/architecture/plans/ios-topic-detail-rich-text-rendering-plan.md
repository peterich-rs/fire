# iOS Topic Detail Rich Text Rendering Plan

Status: proposed (2026-05-31)

Status update (2026-05-31): the native cell path now uses `ASTextNode`'
truncation token for collapsed replies, so `... 展开` stays inline with the last
visible text line and taps route through the text node rather than a separate
button below the body. Collapsed replies suppress their media/poll stack until
expanded, and reply images use bounded reduced render sizes. The remaining rich
text work in this plan is still needed for true block ordering, richer quote,
code, list, table, spoiler, and emoji handling.

## Objective

Make topic-detail cooked-content rendering correct, predictable, and fast on the
native post-cell path. The target is one authoritative rendering stack:
`FireTopicDetailListViewController` -> `FirePostCollectionViewCell` ->
`FirePostRichTextContainerView`, with SwiftUI kept for screen chrome and modal
ownership only.

This plan explicitly does not add a SwiftUI post-row fallback. Rich-text gaps
must be fixed in the native cell, parser, render-content model, or layout cache.

## Current Pipeline

1. Rust parses Discourse `cooked` HTML with `parseCookedHtml` and exports a
   shared AST through UniFFI.
2. iOS `FireRichTextParser` maps that AST into `FireRichTextNode`, extracts
   external post images, filters decorative quote/avatar images, and builds
   plain text.
3. `FireRichTextAttributedStringBuilder` converts nodes to
   `NSAttributedString`.
4. `FireTopicPresentation.detailRenderCache` prepares
   `FireTopicPostRenderContent` per post and reuses cached content when cooked
   HTML and base URL are unchanged.
5. `FireTopicDetailListViewController` builds native post layouts through
   `FirePostLayoutManager`, using estimated heights first and published precise
   TextKit measurements after background computation.
6. `FirePostCollectionViewCell` renders text with
   `FirePostRichTextContainerView` / `ASTextNode`, and renders images, polls,
   reactions, menus, reply shortcuts, and swipe-to-reply directly in UIKit.
   Collapsed replies use an inline `... 展开` truncation token; media and polls
   for those replies are only laid out after expansion.

## Problems To Solve

- Quotes render as inline attributed text today. They need block-level structure
  for clearer indentation, nested quote handling, and whole-quote jump targets.
- Image attachments are extracted into a vertical media stack, so inline order is
  lost for expanded posts that interleave text and images.
- Unknown image dimensions still rely on a generic aspect-ratio fallback.
- Emoji attachments are represented in attributed text, but the native
  `ASTextNode` path does not yet own an explicit async emoji-image rebind flow.
- Code blocks, nested lists, details/spoilers, and tables are currently readable
  but text-like; they need richer native block treatment before they feel close
  to Discourse.
- Dynamic Type and appearance are not first-class render inputs. Layout cache
  invalidates on content-size changes, but attributed strings can still carry
  fonts/colors built under older traits.
- Text selection is not available on the native `ASTextNode` path.
- Height estimation and exact measurement can diverge, causing visible rebinds
  and scroll-budget pressure on long rich posts.

## Design Principles

- Keep Rust responsible for protocol-level cooked HTML parsing and shared AST
  semantics.
- Keep iOS responsible for native text/media layout, interaction, selection,
  image loading, and accessibility.
- Make render inputs explicit: cooked HTML, base URL, content size category,
  interface style, locale-sensitive typography, and parser/render version.
- Prefer structured render blocks over ad hoc string decoration for quotes,
  code, tables, media, and spoilers.
- Use stable tokens for diff/layout identity; never hash whole cooked HTML on the
  scroll-time path.
- Fix the native post cell rather than adding compatibility rendering paths.

## Proposed Model

Introduce a trait-aware rich-text render payload:

```text
FireTopicRichTextRenderInput
  cookedSignature
  baseURLString
  contentSizeCategory
  userInterfaceStyle
  renderVersion

FireTopicRichTextRenderOutput
  blocks: [FireTopicRichTextBlock]
  plainText
  linkTargets
  mediaAttachments
  emojiAttachments
  signature
```

`FireTopicRichTextBlock` should be the layout contract for the native cell. The
first version can keep paragraphs as attributed strings while splitting out
quote, code block, image, list, details, table, and onebox/video as explicit
block cases.

## Phases

### Phase 0: Baseline And Fixtures

- Add fixture-driven tests for quote chrome, nested quotes, linked images,
  letter/avatar images, emoji-only paragraphs, code blocks, nested lists, simple
  tables, details/spoilers, and onebox/video.
- Add layout tests for collapsed long text, Dynamic Type, image aspect ratios,
  and published-layout height changes.
- Add signpost fields for estimated height, measured height, render duration,
  and visible-cell rebind count.

### Phase 1: Trait-Aware Render Content

- Move trait-sensitive attributed-string generation behind an explicit render
  input that includes content size category and appearance.
- Include a render-version token so parser/layout changes invalidate stale
  caches intentionally.
- Keep `FireTopicPostRenderContent` as the bridge payload initially, but make it
  wrap the new rich-text output instead of owning loosely related fields.

### Phase 2: Native Correctness

- Implement async emoji image loading/rebinding for the `ASTextNode` path.
- Promote quote rendering to a dedicated block with author/post metadata and a
  clear jump target.
- Keep code blocks monospaced but give them block padding, copy action, and
  horizontal overflow handling.
- Preserve list nesting depth in the block model rather than flattening all list
  content into prefixed lines.
- Keep table rendering conservative: start with a compact native table/card
  block, not a lossy `A | B` paragraph.

### Phase 3: Measurement And Cache Tightening

- Measure and render from the same trait-aware attributed/block payload.
- Cache exact block heights by post render signature, width, content size
  category, interface style, and render version.
- Bound cache memory and evict by least-recently-used topic/post access.
- Preserve scroll anchors when precise heights replace estimates for visible or
  near-visible rows.

### Phase 4: Selection And Interactions

- Add a selectable text mode for paragraph/code/quote text that suppresses
  swipe-to-reply while selection is active.
- Keep links, mentions, hashtags, topic links, image taps, and quote jump targets
  individually tappable.
- Add accessibility labels/actions for quote jumps, code copy, spoiler reveal,
  image opening, and poll controls.

### Phase 5: Visual Polish

- Improve quote spacing and nested quote indentation.
- Add image frame-aware downsampling and prefetch priority based on working-range
  distance.
- Add code language labels when available.
- Improve details/spoiler reveal state without replacing the row or switching
  render paths.

## Verification

- Unit: `FireTopicPresentationTests`, `FirePostCellLayoutCalculatorTests`,
  `FirePostLayoutManagerTests`, and `FireTopicDetailRuntimeTests`.
- Snapshot-style fixtures: render-content block output for real LinuxDo cooked
  HTML samples.
- Performance: compare scrolling, layout-publish count, rebind count, and memory
  before/after on long posts with quotes, code, images, and polls.
- Regression: topic detail must not reintroduce `FirePostRow`,
  `FireTopicDetailCollectionView`, or hosted SwiftUI post-row fallbacks.
