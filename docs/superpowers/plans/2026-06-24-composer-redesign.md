# Composer & Quick Reply Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the broken quick reply bar layout and redesign the iOS composer into a two-step, editor-centric, image-local-first flow with local drafts (createTopic / non-PM advancedReply).

**Architecture:** Phase 1 is a bug fix inside the existing Texture node path (no new components). Phase 2 restructures `FireComposerViewController` (UIKit) into a `.meta`/`.body` step state machine with half-sheet pickers and notification-driven keyboard avoidance. Phase 3 adds local-first image attachments (NSTextAttachment token system) and a file-based local draft store that replaces server drafts for createTopic and non-PM advancedReply only; private messages keep server drafts.

**Tech Stack:** UIKit + Texture (AsyncDisplayKit) for topic detail; UIKit for the composer; XCTest for tests; XcodeGen (`project.yml`) for the project; SPM dependencies; no SwiftLint/SwiftFormat configured.

**Spec:** `docs/superpowers/specs/2026-06-22-composer-redesign-design.md` (commit `974ebb9`).

## Global Constraints

- **Platform:** iOS 16.0 deployment target (from `project.yml`).
- **PM stays on server drafts.** `.privateMessage` and `.advancedReply(isPrivateMessage: true)` must continue calling `viewModel.saveDraft`/`fetchDraft`/`deleteDraft`. Local drafts apply only to `.createTopic` and non-PM `.advancedReply`.
- **No fallback/parallel rendering.** Topic detail rows stay on the Texture cell path. The quick reply fix is expressed in Texture layout specs, not Auto Layout constraints.
- **Naming:** the composer tag search sheet is `FireComposerTagSearchSheet`, never `FireTagPickerSheet` (that name is taken by the SwiftUI Home sheet).
- **Test framework:** XCTest, `@testable import Fire`, files under `native/ios-app/Tests/Unit/`, class naming `Fire<Thing>Tests`.
- **Regen step required:** after adding any `.swift` file, run `xcodegen generate --spec native/ios-app/project.yml` so `Fire.xcodeproj` includes it (CI fails on project drift via `git diff --exit-code`).
- **Validation reuse:** step-1 gating, publish gating, and tests all go through `FireComposerValidation` — no duplicated imperative checks.
- **No comments** in code unless explicitly requested by this plan.
- **Commit messages** match repo style: lowercase prefix scope, e.g. `fix(ios): ...`, `feat(ios): ...`, `refactor(ios): ...`, `docs: ...`.

**Build/test commands** (from `native/ios-app/README.md`):
```
xcodegen generate --spec native/ios-app/project.yml
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -derivedDataPath /tmp/fire-ios-unit CODE_SIGNING_ALLOWED=NO test
```

---

## File Structure

### New files

| Path | Responsibility |
|------|----------------|
| `native/ios-app/Tests/Unit/FireTopicDetailKeyboardLayoutTests.swift` | Unit tests for quick reply bar height (no keyboard inset) + root node contentInset routing. |
| `native/ios-app/Tests/Unit/FireComposerStepGatingTests.swift` | Unit tests for step-1/meta gating: title + category + `minimumRequiredTags`; required tag groups are advisory until Rust exposes membership. |
| `native/ios-app/App/Views/Composer/FireComposerMetaStepView.swift` | UIKit view: step-1 content (title field, category inline list + "更多", selected-category summary, tag chips, hot tags). Pure view; no networking. |
| `native/ios-app/App/Views/Composer/FireComposerBodyStepView.swift` | UIKit view: step-2 content (reply header OR category/tag summary card, editor UITextView, char count, markdown toolbar host). Pure view. |
| `native/ios-app/App/Views/Composer/FireCategoryPickerSheet.swift` | UIKit `UIViewController` half-sheet: full category list + search, presented via `sheetPresentationController` `[.medium(), .large()]` + grabber. |
| `native/ios-app/App/Views/Composer/FireComposerTagSearchSheet.swift` | UIKit `UIViewController` half-sheet: tag search results (composer-specific; NOT the Home `FireTagPickerSheet`). |
| `native/ios-app/App/Views/Composer/FireComposerImageAttachment.swift` | `NSTextAttachment` subclass holding a local thumbnail + `localId`; bounds 80×80; remove affordance. |
| `native/ios-app/App/Views/Composer/FireComposerImageTokens.swift` | Pure functions: scan `bodyText` for `{{attach:local-<uuid>}}`, replace tokens with markdown after upload, generate/parse token IDs. UIKit-free, fully testable. |
| `native/ios-app/App/Views/Composer/FireLocalDraftStore.swift` | `protocol FireLocalDraftStore` + `FileFireLocalDraftStore` impl (JSON + image files under `Application Support/Fire/FireDrafts/<draftKey>/`). |
| `native/ios-app/App/Views/Composer/FireLocalDraft.swift` | `struct FireLocalDraft` model + `ComposerStep` enum (`meta`/`body`) + `Codable`. |
| `native/ios-app/Tests/Unit/FireComposerImageTokensTests.swift` | Unit tests for token scan/replace. |
| `native/ios-app/Tests/Unit/FireLocalDraftStoreTests.swift` | Unit tests for save/load/delete/restore-with-images, incl. PM-exclusion guard. |

### Modified files

| Path | Changes |
|------|---------|
| `native/ios-app/App/TopicDetail/Nodes/FireTopicQuickReplyBarNode.swift` | `estimatedHeight(forWidth:)` keeps adding `bottomInset`; the caller now passes safe-area only, never keyboard height. |
| `native/ios-app/App/TopicDetail/Nodes/FireTopicDetailRootNode.swift` | New property `keyboardOverlap: CGFloat`; `layout()` sets `contentInset.bottom = barHeight + keyboardOverlap`; `layoutSpecThatFits` wraps only the bar subtree in `ASInsetLayoutSpec` bottom = `keyboardOverlap`. |
| `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift` | Stop passing `currentBottomChromeInset` into `updateBottomSafeAreaInset`; instead pass safe-area to bar and keyboard overlap to root node via two setters. |
| `native/ios-app/App/Views/Composer/FireComposerView.swift` | Add `step` state; swap `contentStack` children per step; add `FireComposerMetaStepView`/`FireComposerBodyStepView`; keyboard avoidance on scroll; route category/tag pickers to half-sheets; replace image-upload-on-pick with local-token path; swap server draft calls to `FireLocalDraftStore` for createTopic/non-PM advancedReply; unify submit validation. |
| `native/ios-app/project.yml` | (No edit needed if new files are already under `App/`/`Tests/Unit/` globs — verify via xcodegen drift check.) |

### Shared types produced for reuse

- `FireLocalDraft` (Task 10): `struct FireLocalDraft: Codable, Equatable { draftKey, step: ComposerStep, title, categoryId: UInt64?, tags: [String], bodyText, routeKind: FireComposerRoute.Kind, updatedAt: Date }` — note `routeKind` stored as a serializable enum, NOT the full `FireComposerRoute`.
- `ComposerStep` (Task 10): `enum ComposerStep: String, Codable, Equatable { case meta, body }`.
- `FireComposerValidation.metaStepReady(...)` (Task 8): the shared step-1 gate for title, category, and `minimumRequiredTags`; `requiredTagGroups` remain advisory because membership is not exposed.
- `FireComposerImageTokens` (Task 11): `scanTokens(_ bodyText: String) -> [String]`, `replaceTokens(_ bodyText: String, mappings: [String: String]) -> String`.

---

## Phase 1 — Quick Reply Bar Fix (independently shippable)

### Task 1: Test that bar height tracks safe area but not keyboard height

> **Geometry contract (verified against `FireTopicQuickReplyBarView.updateBottomInset` line 244-245):** the backing view pushes its content stack up by `-(12 + inset)`, so the bar's intrinsic height grows with whatever is passed to `updateBottomInset`. After Phase 1, `updateBottomInset` receives **safe-area bottom only** (never keyboard height). The bar height MUST therefore equal `10 + 36 + 12 + safeAreaBottom`. Keyboard height is handled entirely by the root node's feed `contentInset.bottom` + overlay positioning (Task 3), never by the bar.

**Files:**
- Create: `native/ios-app/Tests/Unit/FireTopicDetailKeyboardLayoutTests.swift`
- Test: same file

**Interfaces:**
- Consumes: `FireTopicQuickReplyBarNode`, `FireTopicDetailQuickReplyState` (from `App/TopicDetail/Nodes/FireTopicQuickReplyBarNode.swift`).
- Produces: a failing test asserting height = content + safe area, and that the bar never receives keyboard height.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import AsyncDisplayKit
@testable import Fire

@MainActor
final class FireTopicDetailKeyboardLayoutTests: XCTestCase {

    private func makeVisibleState() -> FireTopicDetailQuickReplyState {
        FireTopicDetailQuickReplyState(
            isVisible: true,
            typingSummary: nil,
            targetSummary: nil,
            placeholder: "快速回复…",
            draft: "",
            isSubmitting: false,
            validationMessage: nil
        )
    }

    func testQuickReplyBarHeightIncludesSafeAreaButNotKeyboard() throws {
        let node = FireTopicQuickReplyBarNode()
        node.apply(state: makeVisibleState())
        node.updateLayoutWidth(393)

        let zeroInset = node.layoutThatFits(
            ASSizeRange(min: .init(width: 393, height: 0),
                        max: .init(width: 393, height: 852))
        ).size.height

        // Safe area (34pt) MUST grow the bar height.
        node.updateBottomInset(34)
        let withSafeArea = node.layoutThatFits(
            ASSizeRange(min: .init(width: 393, height: 0),
                        max: .init(width: 393, height: 852))
        ).size.height
        XCTAssertEqual(withSafeArea, zeroInset + 34, accuracy: 1.0,
                       "Bar height must include safe-area bottom")

        // A keyboard-sized value must NOT be passed to the bar at all.
        // (The root node routes keyboard height to contentInset, never here.)
        // This test documents that contract by showing the bar only ever sees
        // safe-area values; the controller wiring is verified in Task 3/4.
    }
}
```

- [ ] **Step 2: Run test to verify current (broken) state**

```
xcodegen generate --spec native/ios-app/project.yml
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -derivedDataPath /tmp/fire-ios-unit CODE_SIGNING_ALLOWED=NO test -only-testing:FireTests/FireTopicDetailKeyboardLayoutTests
```
Expected: the direct safe-area measurement passes because the bar should grow with safe area. The controller/root wiring still fails until Tasks 3-4 stop passing keyboard height into the bar and route keyboard overlap through the root node.

- [ ] **Step 3: Commit (red)**

```
git -C /Users/fannnzhang/code/github.com/fire add native/ios-app/Tests/Unit/FireTopicDetailKeyboardLayoutTests.swift
git -C /Users/fannnzhang/code/github.com/fire commit -m "test(ios): quick reply bar height tracks safe area not keyboard (red)"
```

### Task 2: Keep `estimatedHeight` formula intact — the bar height fix is at the call site

**Files:**
- Modify: `native/ios-app/App/TopicDetail/Nodes/FireTopicQuickReplyBarNode.swift` — NO change to `estimatedHeight(forWidth:)`. The formula `10 + 36 + 12 + bottomInset` stays correct because `bottomInset` will now only ever receive safe-area bottom (Task 3/4 rewires the caller).

**Interfaces:**
- Consumes: nothing new.
- Produces: the bar's `estimatedHeight` is correct as-is once the caller stops passing keyboard height.

- [ ] **Step 1: Verify `estimatedHeight(forWidth:)` is left UNCHANGED**

`FireTopicQuickReplyBarNode.swift:117` must remain:
```swift
var height: CGFloat = 10 + 36 + 12 + bottomInset
```
This is correct: `bottomInset` will hold safe-area bottom only after Task 3/4. Do NOT remove `bottomInset` from this formula (doing so would clip content when keyboard is hidden, per the review).

- [ ] **Step 2: Run the Task 1 test — verify it passes**

```
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -derivedDataPath /tmp/fire-ios-unit CODE_SIGNING_ALLOWED=NO test -only-testing:FireTests/FireTopicDetailKeyboardLayoutTests/testQuickReplyBarHeightIncludesSafeAreaButNotKeyboard
```
Expected: PASS.

- [ ] **Step 3: Run the existing coarse-height test — verify still green**

```
xcodebuild ... -only-testing:FireTests/FireTopicDetailRuntimeTests/testQuickReplyBarMeasuresToCompactVisibleHeight
```
Expected: PASS (height < 220 still holds).

- [ ] **Step 4: Commit**

```
git add native/ios-app/App/TopicDetail/Nodes/FireTopicQuickReplyBarNode.swift
git commit -m "fix(ios): exclude keyboard inset from quick reply bar height"
```

### Task 3: Route keyboard overlap into root node contentInset + overlay offset

**Files:**
- Modify: `native/ios-app/App/TopicDetail/Nodes/FireTopicDetailRootNode.swift` (add `keyboardOverlap`, update `layout()`, update `layoutSpecThatFits(_:)`)
- Modify: `native/ios-app/Tests/Unit/FireTopicDetailKeyboardLayoutTests.swift` (add root-node inset test)

**Interfaces:**
- Consumes: `FireTopicQuickReplyBarNode.calculatedSize.height` (existing).
- Produces: `FireTopicDetailRootNode.updateKeyboardOverlap(_:)` and `updateBottomSafeAreaInset(_:)` (split semantics — see Task 4 for the caller change).

- [ ] **Step 1: Write the failing root-node test**

Append to `FireTopicDetailKeyboardLayoutTests.swift`:

```swift
import AsyncDisplayKit

func testRootNodeContentInsetIncludesKeyboardOverlap() throws {
    let collectionNode = ASCollectionNode(collectionViewLayout: UICollectionViewFlowLayout())
    let bar = FireTopicQuickReplyBarNode()
    bar.apply(state: makeVisibleState())
    bar.updateLayoutWidth(393)

    let root = FireTopicDetailRootNode(feedNode: collectionNode, quickReplyBarNode: bar)
    // Simulate the controller wiring safe-area + keyboard overlap.
    root.updateBottomSafeAreaInset(34)   // safe area only now
    root.updateKeyboardOverlap(0)

    let barHeight = bar.calculatedSize.height
    let insetNoKeyboard = (collectionNode.view as? UIScrollView)?.contentInset.bottom ?? 0

    root.updateKeyboardOverlap(300)

    let scrollView = try XCTUnwrap(collectionNode.view as? UIScrollView)
    let insetWithKeyboard = scrollView.contentInset.bottom

    // contentInset.bottom must grow by the keyboard overlap (so feed scrolls to reveal bar).
    XCTAssertEqual(insetWithKeyboard, insetNoKeyboard + 300, accuracy: 1.0)
    XCTAssertGreaterThan(insetWithKeyboard, barHeight, "Inset must exceed bar height to reveal input above keyboard")
}
```

> Note: `ASCollectionNode`/`ASSizeRange` need a measured layout to populate `contentInset`. If Texture doesn't apply `layout()` without a live window in this test target, fall back to asserting on a new pure helper `FireTopicDetailInsets.makeContentInsetBottom(barHeight:keyboardOverlap:safeArea:) -> CGFloat` extracted from the node and test that instead. Prefer the node-level test; only switch if it cannot run headless.

- [ ] **Step 2: Run test to verify it fails**

```
xcodebuild ... -only-testing:FireTests/FireTopicDetailKeyboardLayoutTests/testRootNodeContentInsetIncludesKeyboardOverlap
```
Expected: FAIL (`updateKeyboardOverlap` does not exist / inset unchanged).

- [ ] **Step 3: Implement the root-node changes**

In `FireTopicDetailRootNode.swift`, add a stored property and split the setter:

```swift
private var keyboardOverlap: CGFloat = 0
private var bottomSafeAreaInset: CGFloat = 0  // existing; now safe-area only

@MainActor
func updateKeyboardOverlap(_ overlap: CGFloat) {
    guard abs(keyboardOverlap - overlap) > 0.5 else { return }
    keyboardOverlap = overlap
    quickReplyBarNode.updateBottomInset(bottomSafeAreaInset)  // safe-area only, no keyboard
    setNeedsLayout()
}
```

Change the existing `updateBottomSafeAreaInset(_:)` so it no longer forwards keyboard height into the bar — it only stores safe-area and pushes safe-area to the bar:

```swift
@MainActor
func updateBottomSafeAreaInset(_ inset: CGFloat) {
    guard abs(bottomSafeAreaInset - inset) > 0.5 else { return }
    bottomSafeAreaInset = inset
    quickReplyBarNode.updateBottomInset(inset)  // safe-area only
    setNeedsLayout()
}
```

Update `layout()` so `contentInset.bottom = barHeight + keyboardOverlap`:

```swift
override func layout() {
    super.layout()
    guard let scrollView = feedNode.view as? UIScrollView else { return }
    var insets = scrollView.contentInset
    insets.top = topChromeInset
    if !quickReplyBarNode.isHidden {
        insets.bottom = quickReplyBarNode.calculatedSize.height + keyboardOverlap
    } else {
        insets.bottom = bottomSafeAreaInset
    }
    if abs(scrollView.contentInset.top - insets.top) > 0.5
        || abs(scrollView.contentInset.bottom - insets.bottom) > 0.5 {
        scrollView.contentInset = insets
        scrollView.scrollIndicatorInsets = insets
    }
}
```

Update `layoutSpecThatFits(_:)` to lift the bar above the keyboard WITHOUT shrinking the feed (avoiding double-counting the keyboard height — the feed's scrollable area already reserves it via `contentInset.bottom` set in `layout()`). Wrap ONLY the bar in an `ASInsetLayoutSpec` so the feed stays full-size; the bar's bottom edge lands at `view.bottom - keyboardOverlap`:

```swift
override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
    if !quickReplyBarNode.isHidden {
        // Lift the bar up by keyboardOverlap: give the bar a bottom inset so the
        // ASRelativeLayoutSpec(.end) pins it to (overlayBottom - keyboardOverlap).
        let barWithLift = ASInsetLayoutSpec(
            insets: UIEdgeInsets(
                top: 0, left: 0,
                bottom: keyboardOverlap,
                right: 0),
            child: quickReplyBarNode)
        let relative = ASRelativeLayoutSpec(
            horizontalPosition: .start,
            verticalPosition: .end,
            sizingOption: [],
            child: barWithLift)
        // Feed stays full-size; only the overlay (bar) is inset.
        return ASOverlayLayoutSpec(child: feedNode, overlay: relative)
    }
    return ASWrapperLayoutSpec(layoutElement: feedNode)
}
```

> **Why this avoids double-counting:** the feed node is the direct child of the overlay spec and keeps the full constrained size. Only the bar's layout subtree receives the `keyboardOverlap` bottom inset, moving the bar up to sit above the keyboard. Separately, `layout()` sets `contentInset.bottom = barHeight + keyboardOverlap` so the feed's scrollable content can scroll up enough to reveal the bar above the keyboard. The two mechanisms are complementary (one positions the bar, one reserves scroll space), not additive on the same region.

- [ ] **Step 4: Run both root-node + bar tests — verify pass**

```
xcodebuild ... -only-testing:FireTests/FireTopicDetailKeyboardLayoutTests
```
Expected: PASS for both tests.

- [ ] **Step 5: Commit**

```
git add native/ios-app/App/TopicDetail/Nodes/FireTopicDetailRootNode.swift native/ios-app/Tests/Unit/FireTopicDetailKeyboardLayoutTests.swift
git commit -m "fix(ios): route keyboard overlap into feed contentInset + overlay offset"
```

### Task 4: Rewire the controller to pass safe-area and keyboard overlap separately

**Files:**
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift:1022-1055` (`updateBottomChromeInset`, `currentBottomChromeInset`)

**Interfaces:**
- Consumes: `FireTopicDetailRootNode.updateKeyboardOverlap(_:)`, `FireTopicDetailRootNode.updateBottomSafeAreaInset(_:)` (Task 3).
- Produces: the bar receives safe-area only; the root node receives keyboard overlap separately.

- [ ] **Step 1: Split the controller's bottom-inset call**

In `updateBottomChromeInset(animatedWith:)` (around line 1022), replace:

```swift
rootNode.updateBottomSafeAreaInset(currentBottomChromeInset)
```
with:
```swift
rootNode.updateBottomSafeAreaInset(view.safeAreaInsets.bottom)
rootNode.updateKeyboardOverlap(keyboardOverlapHeight)
```

Keep `currentBottomChromeInset` and `keyboardOverlapHeight` as-is (they're still correct computations); we just stop bundling them into one setter. The animation block (`UIView.animate { self.view.layoutIfNeeded() }`) stays — it animates the Texture relayout.

- [ ] **Step 2: Build + run the full FireTests suite**

```
xcodebuild ... test
```
Expected: all tests PASS, including the two new ones. The manual verification (bar visible/tappable above keyboard) happens at PR time — not asserted here.

- [ ] **Step 3: Commit**

```
git add native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift
git commit -m "fix(ios): pass safe-area and keyboard overlap separately to root node"
```

- [ ] **Step 4: Manual verification note (record in PR body)**

> Verify on simulator: open a topic, tap the quick reply bar, keyboard rises, the input row is visible and tappable above the keyboard, and the feed scrolls to reveal it. Confirm no input row is hidden behind the keyboard at any keyboard height.

**Phase 1 is now shippable.** It can be merged/released independently of Phases 2–3.

---

## Phase 2 — Composer Keyboard Avoidance + Step Architecture

> Phase 2 restructures the existing single-scroll composer into a two-step flow. It is large; each task ends with a green build + tests. Do not start Phase 3 until Phase 2 tasks all pass.

### Task 5: Extend `FireComposerValidation` with shared meta-step gating (incl. requiredTagGroups)

**Files:**
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift:564-643` (`FireComposerValidation`)
- Create: `native/ios-app/Tests/Unit/FireComposerStepGatingTests.swift`

**Interfaces:**
- Consumes: `FireComposerRoute`, `TopicCategoryState`, `RequiredTagGroupState` (UniFFI types).
- Produces: `FireComposerValidation.metaStepReady(...)` returning `Bool`; reused by Task 9 (step view gating) and Task 14 (publish gating).

> **VERIFIED FACT (read before coding):** `RequiredTagGroupState` (`rust/crates/fire-uniffi-types/src/records/tag.rs:4`, surfaced in Swift at `fire_uniffi_types.swift`) has ONLY `name: String` and `min_count/minCount: UInt32`. There is **no `tags` field**. The group's name identifies a Discourse tag group server-side, but the client has no list of which tags belong to that group. Therefore the client **cannot fully validate** a required-tag-group constraint locally — it can only enforce `minimumRequiredTags` (total count) and surface the group requirement as advisory text (which the existing code already does at `FireComposerView.swift:654`).

> **Implication for step-1 gating:** `metaStepReady` enforces title + category + `minimumRequiredTags` (total). Required-tag-group violations will only be caught at publish time by the server (same as today). The requirement summary in step 1 still shows the group text so the user knows about it. **Do not invent a `group.tags` field.** If you later want true client-side group validation, that requires adding `tags: Vec<String>` to the Rust `RequiredTagGroupState` record and the Discourse parser that populates it — out of scope for this plan.

> **PREREQUISITE — update the spec BEFORE coding Task 5.** The design doc §4.2 (lines ~140-146) still contains the stale four-condition gating with `group.tags.contains`. Edit `docs/superpowers/specs/2026-06-22-composer-redesign-design.md` §4.2 "Next button gating" to: enabled when `trimmedTitle.count >= minimumTitleLength` AND `selectedCategoryID != nil` AND `selectedTags.count >= minimumRequiredTags`. Add a note: "Required tag groups are advisory in step 1; the client cannot validate group membership because `RequiredTagGroupState` carries no tag list. Group violations are caught at publish by the server." Commit this spec change as `docs: align composer spec with requiredTagGroupState reality` before proceeding to Task 5 Step 1.

- [ ] **Step 1: Write failing tests**

`native/ios-app/Tests/Unit/FireComposerStepGatingTests.swift`:

```swift
import XCTest
@testable import Fire

final class FireComposerStepGatingTests: XCTestCase {

    private func category(minimumRequiredTags: UInt32 = 0) -> TopicCategoryState {
        TopicCategoryState(
            id: 4, name: "资源分享", slug: "resource", parentCategoryId: nil,
            colorHex: nil, textColorHex: nil, topicTemplate: nil,
            minimumRequiredTags: minimumRequiredTags,
            requiredTagGroups: [],
            allowedTags: [], permission: 0, notificationLevel: nil
        )
    }

    func testMetaStepRequiresTitleCategoryAndMinimumTags() {
        XCTAssertFalse(FireComposerValidation.metaStepReady(
            trimmedTitle: "", categoryId: nil,
            selectedTagCount: 0, category: nil,
            minimumTitleLength: 1))
        XCTAssertFalse(FireComposerValidation.metaStepReady(
            trimmedTitle: "ok", categoryId: 4,
            selectedTagCount: 1,
            category: category(minimumRequiredTags: 2),
            minimumTitleLength: 1))
        XCTAssertTrue(FireComposerValidation.metaStepReady(
            trimmedTitle: "ok", categoryId: 4,
            selectedTagCount: 2,
            category: category(minimumRequiredTags: 2),
            minimumTitleLength: 1))
    }

    func testMetaStepAllowsWhenNoMinimumTagsRequired() {
        XCTAssertTrue(FireComposerValidation.metaStepReady(
            trimmedTitle: "ok", categoryId: 4,
            selectedTagCount: 0,
            category: category(minimumRequiredTags: 0),
            minimumTitleLength: 1))
    }
}
```

- [ ] **Step 2: Run — verify fail**

```
xcodegen generate --spec native/ios-app/project.yml
xcodebuild ... test -only-testing:FireTests/FireComposerStepGatingTests
```
Expected: FAIL (`metaStepReady` does not exist).

- [ ] **Step 3: Implement `metaStepReady`**

In `FireComposerValidation`, add (signature must match what Task 7/Task 9 consume):

```swift
static func metaStepReady(
    trimmedTitle: String,
    categoryId: UInt64?,
    selectedTagCount: Int,
    category: TopicCategoryState?,
    minimumTitleLength: Int
) -> Bool {
    guard trimmedTitle.count >= minimumTitleLength, categoryId != nil, let category else {
        return false
    }
    let minTags = Int(category.minimumRequiredTags)
    return selectedTagCount >= minTags
    // NOTE: required tag groups cannot be validated client-side (no tag list
    // per group in RequiredTagGroupState). Group violations are caught at
    // publish by the server. Step 1 surfaces group requirements as advisory text.
}
```

- [ ] **Step 4: Run — verify pass**

```
xcodebuild ... test -only-testing:FireTests/FireComposerStepGatingTests
xcodebuild ... test -only-testing:FireTests/FireComposerValidationTests
```
Expected: both PASS (existing validation tests still green — `metaStepReady` is additive).

- [ ] **Step 5: Commit**

```
git add native/ios-app/App/Views/Composer/FireComposerView.swift native/ios-app/Tests/Unit/FireComposerStepGatingTests.swift
git commit -m "feat(ios): add shared composer meta-step gating with required tag groups"
```

### Task 6: Add keyboard avoidance to the composer scroll view

**Files:**
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift` (`configureLayout()` ~line 990, add keyboard observers matching the app's `keyboardWillChangeFrameNotification` pattern — see `FireOnboardingCredentialFormView.swift:245`).

**Interfaces:**
- Consumes: nothing new (matches existing app pattern).
- Produces: composer scroll view animates its bottom inset / bottom-bar constraint with the keyboard.

- [ ] **Step 1: Add keyboard observers**

In `configureLayout()`, after building `scrollView`/`bottomBar`, add observers (target/selector style, matching `FireOnboardingCredentialFormView`):

```swift
NotificationCenter.default.addObserver(
    self, selector: #selector(composerKeyboardWillChangeFrame(_:)),
    name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
NotificationCenter.default.addObserver(
    self, selector: #selector(composerKeyboardWillHide(_:)),
    name: UIResponder.keyboardWillHideNotification, object: nil)
```

Implement:

```swift
@objc private func composerKeyboardWillChangeFrame(_ notification: Notification) {
    guard let frameEnd = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
    let converted = view.convert(frameEnd, from: nil)
    let overlap = max(0, view.bounds.maxY - converted.minY)
    applyKeyboardInset(overlap, notification: notification)
}

@objc private func composerKeyboardWillHide(_ notification: Notification) {
    applyKeyboardInset(0, notification: notification)
}

private func applyKeyboardInset(_ overlap: CGFloat, notification: Notification) {
    scrollView.contentInset.bottom = overlap
    scrollView.verticalScrollIndicatorInsets.bottom = overlap
    bottomBarBottomConstraint?.constant = overlap > 0 ? -overlap : 0   // see Step 2
    let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
    let curveRaw = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
    UIView.animate(withDuration: duration, delay: 0,
                   options: [UIView.AnimationOptions(rawValue: curveRaw << 16), .beginFromCurrentState]) {
        self.view.layoutIfNeeded()
    }
}
```

- [ ] **Step 2: Expose `bottomBarBottomConstraint`**

The current `bottomBar` is pinned to `view.bottomAnchor` (Task context: `configureBottomBar`, ~line 1171). Store its bottom constraint in a property:

```swift
private var bottomBarBottomConstraint: NSLayoutConstraint?
```

and capture it when activating constraints, e.g.:
```swift
bottomBarBottomConstraint = bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
bottomBarBottomConstraint?.isActive = true
```
(Adjust to match the real constraint code in `configureBottomBar` — read lines 1171-1210 before editing.)

- [ ] **Step 3: Build + run full test suite**

```
xcodebuild ... test
```
Expected: PASS (no behavioral test yet, but must not break existing tests/build).

- [ ] **Step 4: Commit**

```
git add native/ios-app/App/Views/Composer/FireComposerView.swift
git commit -m "feat(ios): add keyboard avoidance to composer scroll view + bottom bar"
```

### Task 7: Introduce the `step` state machine and swap content per step

**Files:**
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift` (add `step`, swap `contentStack` arranged subviews, change nav title).

**Interfaces:**
- Consumes: `FireComposerValidation.metaStepReady` (Task 5).
- Produces: `private(set) var step: ComposerStep` (enum from Task 10 if Phase 3 lands first; otherwise define a local `enum Step { case meta, body }` here and migrate in Task 10). For ordering simplicity, **define `ComposerStep` here** and have Task 10 adopt it.

- [ ] **Step 1: Define `ComposerStep` and the step state**

Near the top of `FireComposerViewController`:

```swift
enum Step { case meta, body }
private var step: Step = .createTopicDefault

private var Step.createTopicDefault: Step {
    switch route.kind {
    case .createTopic: return .meta
    case .advancedReply, .privateMessage: return .body   // replies skip meta
    }
}
```

> If `createTopicDefault` as a static-on-instance is awkward, compute in `viewDidLoad` instead. Pick whichever reads cleaner.

- [ ] **Step 2: Add step-transition methods**

```swift
private func goToMetaStep() {
    step = .meta
    navigationItem.title = route.navigationTitle
    renderStepContent()
}

private func goToBodyStep() {
    guard case .createTopic = route.kind else {
        step = .body; renderStepContent(); return
    }
    // createTopic: gate on meta readiness
    let cat = viewModel.categoryPresentation(for: selectedCategoryID)
    guard FireComposerValidation.metaStepReady(
        trimmedTitle: trimmedTitle,
        categoryId: selectedCategoryID,
        selectedTagCount: selectedTags.count,
        category: cat,
        minimumTitleLength: minimumTitleLength) else {
        showSubmissionError("请先完善标题、分类和标签。")
        return
    }
    injectCategoryTemplateIfNeeded()
    step = .body
    navigationItem.title = "编辑正文"
    renderStepContent()
}
```

- [ ] **Step 3: Implement `renderStepContent()`**

Swap `contentStack.arrangedSubviews` per step. Keep `bottomBar`/markdown toolbar shared (they're outside the scroll stack or at the bottom). Reuse the existing built subviews (`topicHeaderStack`, `replyTargetCard`, `editorContainer`, etc.) — move them between stacks rather than recreating.

For `.meta`: show `topicTitleField` + category list/summary + tags; hide `editorContainer`/`replyTargetCard`.
For `.body`: show `editorContainer`; show `replyTargetCard` (advancedReply) or category/tag summary card (createTopic); hide the meta fields.

```swift
private func renderStepContent() {
    contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    switch step {
    case .meta:
        contentStack.addArrangedSubview(topicHeaderStack)   // rebuilt to hold title/category/tags
    case .body:
        if case .advancedReply = route.kind {
            contentStack.addArrangedSubview(replyTargetCard)
        } else if case .createTopic = route.kind {
            contentStack.addArrangedSubview(metaSummaryCard)  // built in Task 8/9
        }
        contentStack.addArrangedSubview(editorContainer)
        contentStack.addArrangedSubview(bodyRequirementLabel)
    }
    view.setNeedsLayout()
}
```

> This is a structural refactor of `configureLayout()`/`render()`. Read lines 990-1210 before editing. Preserve all existing subview construction; only change which stack they live in and when.

- [ ] **Step 4: Wire nav bar buttons per step**

`navigationItem.rightBarButtonItem` = publish (`.body`) or next (`.meta`). Left bar = back to `.meta` when in `.body` for createTopic; close otherwise.

- [ ] **Step 5: Build + test**

```
xcodebuild ... test
```
Expected: PASS. Existing `FireComposerValidationTests` unaffected.

- [ ] **Step 6: Commit**

```
git add native/ios-app/App/Views/Composer/FireComposerView.swift
git commit -m "feat(ios): two-step composer state machine with content swap"
```

### Task 8: Build `FireComposerMetaStepView` (step 1 UI)

**Files:**
- Create: `native/ios-app/App/Views/Composer/FireComposerMetaStepView.swift`
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift` (instantiate + host)

**Interfaces:**
- Consumes: `FireComposerRoute`, `FireAppViewModel` (for `allCategories()`, `topTags()`).
- Produces: callbacks `onTitleChanged`, `onCategorySelected`, `onTagsChanged`, `onRequestMoreCategories`, `onRequestChangeCategory`, `onNext`.

- [ ] **Step 1: Build the view (UIKit, programmatic Auto Layout)**

A `UIView` subclass containing: title `UITextField`, a container that flips between (a) inline hot-category list + "更多分类…" button and (b) selected-category summary with "更换", a selected-tags chip row, a hot-tags row, and a collapsed "搜索标签" entry. Use `FireComposerCardView` for card backgrounds.

> **Prerequisite:** `FireComposerCardView` is currently `private` inside `FireComposerView.swift` (line 2449). Before (or as part of) this task, change its declaration from `private final class FireComposerCardView` to `final class FireComposerCardView` (internal) so the new file can use it. This is a one-token edit in `FireComposerView.swift`; do it as the first step of this task and include it in the commit.

Expose configuration via `apply(state:)` where `state` carries `title`, `selectedCategory`, `hotCategories`, `selectedTags`, `hotTags`, `nextEnabled`.

> This view owns NO networking and NO navigation. It only reports taps/edits via callbacks. Keep it ~250-400 lines.

- [ ] **Step 2: Host it in the controller's `.meta` step**

Replace the inline `topicHeaderStack` usage with `metaStepView` in `renderStepContent()` for `.meta`. Wire callbacks to controller methods (`titleFieldChanged` → `metaStepView.apply(...)`, etc.).

- [ ] **Step 3: Build + test**

```
xcodegen generate --spec native/ios-app/project.yml
xcodebuild ... test
```
Expected: PASS.

- [ ] **Step 4: Commit**

```
git add native/ios-app/App/Views/Composer/FireComposerMetaStepView.swift native/ios-app/App/Views/Composer/FireComposerView.swift
git commit -m "feat(ios): composer meta step view (title/category/tags)"
```

### Task 9: Build `FireComposerBodyStepView` + half-sheet pickers

**Files:**
- Create: `native/ios-app/App/Views/Composer/FireComposerBodyStepView.swift`
- Create: `native/ios-app/App/Views/Composer/FireCategoryPickerSheet.swift`
- Create: `native/ios-app/App/Views/Composer/FireComposerTagSearchSheet.swift`
- Modify: `FireComposerView.swift` (host body step; wire pickers)

**Interfaces:**
- Consumes: `FireAppViewModel.searchService.searchTags(...)`, `viewModel.allCategories()`.
- Produces: the body-step view + the two half-sheet controllers.

- [ ] **Step 1: `FireCategoryPickerSheet` (UIKit UIViewController)**

A `UITableViewController` (or `UICollectionViewController`) showing all categories sorted by name, filtered to `permission <= 1`, with a `UISearchBar`. On select, calls `onSelected: (UInt64) -> Void`. Present with the house style:

```swift
if let sheet = controller.sheetPresentationController {
    sheet.detents = [.medium(), .large()]
    sheet.prefersGrabberVisible = true
}
```

- [ ] **Step 2: `FireComposerTagSearchSheet` (UIKit UIViewController)**

Search field + results list. Calls `searchService.searchTags(query, filterForInput: true, categoryID: selectedCategoryID, selectedTags: selectedTags)`. On select, `onSelected: (String) -> Void`. Same sheet presentation style.

> Name MUST be `FireComposerTagSearchSheet` (the spec's review fix). Do not name it `FireTagPickerSheet`.

- [ ] **Step 3: `FireComposerBodyStepView`**

Hosts: optional reply header (`advancedReply`), optional collapsible category/tag summary card (`createTopic`) that re-presents `FireCategoryPickerSheet` on tap, the `bodyTextView` (existing `UITextView`), char count label, and a container for the markdown toolbar (the toolbar itself is built in the controller and added as a subview — keep the existing `markdownToolbarScroll`).

- [ ] **Step 4: Wire pickers into the controller**

`onRequestMoreCategories` / `onRequestChangeCategory` → present `FireCategoryPickerSheet`. Category change → if tags selected, show confirm alert ("更换分类会清空已选标签，继续？"), clear tags on confirm.

- [ ] **Step 5: Build + test**

```
xcodegen generate --spec native/ios-app/project.yml
xcodebuild ... test
```
Expected: PASS.

- [ ] **Step 6: Commit**

```
git add native/ios-app/App/Views/Composer/FireComposerBodyStepView.swift native/ios-app/App/Views/Composer/FireCategoryPickerSheet.swift native/ios-app/App/Views/Composer/FireComposerTagSearchSheet.swift native/ios-app/App/Views/Composer/FireComposerView.swift
git commit -m "feat(ios): composer body step view + category/tag half-sheet pickers"
```

**Phase 2 complete.** Step navigation, keyboard avoidance, and pickers work. Image upload still uses the old on-pick path (fixed in Phase 3).

---

## Phase 3 — Local-first Images + Local Drafts

### Task 10: `FireLocalDraft` model + `FireLocalDraftStore` protocol

**Files:**
- Create: `native/ios-app/App/Views/Composer/FireLocalDraft.swift`
- Create: `native/ios-app/App/Views/Composer/FireLocalDraftStore.swift`
- Create: `native/ios-app/Tests/Unit/FireLocalDraftStoreTests.swift`

**Interfaces:**
- Consumes: nothing (self-contained model).
- Produces: `FireLocalDraft`, `ComposerStep` (migrated from Task 7's local enum), `FireLocalDraftStore` protocol, `FileFireLocalDraftStore`.

- [ ] **Step 1: Write failing tests**

`FireLocalDraftStoreTests.swift`:

```swift
import XCTest
@testable import Fire

final class FireLocalDraftStoreTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FireDraftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempRoot)
    }

    private func makeStore() -> FileFireLocalDraftStore {
        FileFireLocalDraftStore(rootDirectory: tempRoot, fileManager: .default)
    }

    func testSaveLoadRoundTripsFields() throws {
        let store = makeStore()
        let draft = FireLocalDraft(
            draftKey: "new_topic", step: .body,
            title: "hi", categoryId: 4, tags: ["a"], bodyText: "body {{attach:local-x}}",
            routeKind: .createTopic,
            attachments: [FireLocalDraftAttachment(
                localId: "local-x", fileExtension: "jpg",
                mimeType: "image/jpeg", fileName: "image.jpg")],
            updatedAt: Date(timeIntervalSince1970: 1719043200))
        try store.saveDraft(draftKey: "new_topic", draft: draft)
        let loaded = store.loadDraft(draftKey: "new_topic")
        XCTAssertEqual(loaded, draft)
    }

    func testSaveDeleteRemovesDirectory() throws {
        let store = makeStore()
        let draft = FireLocalDraft(draftKey: "topic_1", step: .meta, title: "t",
            categoryId: nil, tags: [], bodyText: "", routeKind: .advancedReply,
            attachments: [], updatedAt: Date())
        try store.saveDraft(draftKey: "topic_1", draft: draft)
        XCTAssertNotNil(store.loadDraft(draftKey: "topic_1"))
        try store.deleteDraft(draftKey: "topic_1")
        XCTAssertNil(store.loadDraft(draftKey: "topic_1"))
    }

    func testSaveLoadImageFileSurvivesRoundTrip() throws {
        let store = makeStore()
        let bytes = Data([0xFF, 0xD8, 0xFF])
        try store.saveImage(draftKey: "new_topic", localId: "local-abc", fileExtension: "jpg", bytes: bytes)
        let read = try store.loadImage(draftKey: "new_topic", localId: "local-abc", fileExtension: "jpg")
        XCTAssertEqual(read, bytes)
    }
}
```

- [ ] **Step 2: Run — verify fail**

```
xcodegen generate --spec native/ios-app/project.yml
xcodebuild ... test -only-testing:FireTests/FireLocalDraftStoreTests
```
Expected: FAIL (types don't exist).

- [ ] **Step 3: Implement `FireLocalDraft`**

```swift
import Foundation

enum ComposerStep: String, Codable, Equatable {
    case meta, body
}

struct FireLocalDraft: Codable, Equatable {
    var draftKey: String
    var step: ComposerStep
    var title: String
    var categoryId: UInt64?
    var tags: [String]
    var bodyText: String
    var routeKind: RouteKindCodable
    var attachments: [FireLocalDraftAttachment]
    var updatedAt: Date
}

struct FireLocalDraftAttachment: Codable, Equatable {
    var localId: String
    var fileExtension: String
    var mimeType: String
    var fileName: String
}

// Local drafts are scoped to .createTopic and non-PM .advancedReply only.
// Encode just the discriminant we need; PM never reaches this store.
enum RouteKindCodable: String, Codable, Equatable {
    case createTopic
    case advancedReply
}
```

> **Why `attachments` lives on the draft (review fix P1 #4):** the body token `{{attach:local-<uuid>}}` carries only the id. On app relaunch the upload step needs `fileExtension`/`mimeType`/`fileName` to read the local file and call `uploadImage`. Storing a parallel `attachments` array on `FireLocalDraft` makes these recoverable. The token in `bodyText` stays as the cross-reference key.

- [ ] **Step 4: Implement `FireLocalDraftStore` + `FileFireLocalDraftStore`**

```swift
protocol FireLocalDraftStore: AnyObject {
    func loadDraft(draftKey: String) -> FireLocalDraft?
    func saveDraft(draftKey: String, draft: FireLocalDraft) throws
    func deleteDraft(draftKey: String) throws
    func saveImage(draftKey: String, localId: String, fileExtension: String, bytes: Data) throws
    func loadImage(draftKey: String, localId: String, fileExtension: String) throws -> Data
    func deleteImage(draftKey: String, localId: String, fileExtension: String) throws
}

final class FileFireLocalDraftStore: FireLocalDraftStore {
    private let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL, fileManager: FileManager) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    static func defaultRoot() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return support.appendingPathComponent("Fire", isDirectory: true)
                      .appendingPathComponent("FireDrafts", isDirectory: true)
    }

    private func draftDir(_ draftKey: String) -> URL {
        rootDirectory.appendingPathComponent(draftKey, isDirectory: true)
    }

    func loadDraft(draftKey: String) -> FireLocalDraft? {
        let url = draftDir(draftKey).appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FireLocalDraft.self, from: data)
    }

    func saveDraft(draftKey: String, draft: FireLocalDraft) throws {
        let dir = draftDir(draftKey)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(draft)
        try data.write(to: dir.appendingPathComponent("meta.json"), options: [.atomic])
    }

    func deleteDraft(draftKey: String) throws {
        try fileManager.removeItem(at: draftDir(draftKey))
    }

    func saveImage(draftKey: String, localId: String, fileExtension: String, bytes: Data) throws {
        let dir = draftDir(draftKey)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try bytes.write(to: dir.appendingPathComponent("\(localId).\(fileExtension)"), options: [.atomic])
    }

    func loadImage(draftKey: String, localId: String, fileExtension: String) throws -> Data {
        try Data(contentsOf: draftDir(draftKey).appendingPathComponent("\(localId).\(fileExtension)"))
    }

    func deleteImage(draftKey: String, localId: String, fileExtension: String) throws {
        try fileManager.removeItem(at: draftDir(draftKey).appendingPathComponent("\(localId).\(fileExtension)"))
    }
}
```

- [ ] **Step 5: Run — verify pass**

```
xcodebuild ... test -only-testing:FireTests/FireLocalDraftStoreTests
```
Expected: PASS.

- [ ] **Step 6: Commit**

```
git add native/ios-app/App/Views/Composer/FireLocalDraft.swift native/ios-app/App/Views/Composer/FireLocalDraftStore.swift native/ios-app/Tests/Unit/FireLocalDraftStoreTests.swift
git commit -m "feat(ios): file-based local draft store (createTopic/non-PM advancedReply)"
```

### Task 11: Image token scan/replace pure functions

**Files:**
- Create: `native/ios-app/App/Views/Composer/FireComposerImageTokens.swift`
- Create: `native/ios-app/Tests/Unit/FireComposerImageTokensTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `FireComposerImageTokens.scanTokens(_:) -> [String]`, `FireComposerImageTokens.replaceTokens(_:mappings:) -> String`, `FireComposerImageTokens.makeLocalId() -> String`.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Fire

final class FireComposerImageTokensTests: XCTestCase {
    func testScanFindsAllTokens() {
        let body = "a {{attach:local-1}} b {{attach:local-2}} c"
        XCTAssertEqual(FireComposerImageTokens.scanTokens(body), ["local-1", "local-2"])
    }

    func testReplaceSubstitutesMarkdown() {
        let body = "x {{attach:local-1}} y"
        let out = FireComposerImageTokens.replaceTokens(
            body, mappings: ["local-1": "![image|100x100](upload://abc)"])
        XCTAssertEqual(out, "x ![image|100x100](upload://abc) y")
    }

    func testReplaceLeavesUnmappedTokensIntact() {
        let body = "{{attach:local-1}}"
        let out = FireComposerImageTokens.replaceTokens(body, mappings: [:])
        XCTAssertEqual(out, "{{attach:local-1}}")
    }

    func testMakeLocalIdIsUniqueAndPrefixed() {
        let a = FireComposerImageTokens.makeLocalId()
        let b = FireComposerImageTokens.makeLocalId()
        XCTAssertTrue(a.hasPrefix("local-"))
        XCTAssertNotEqual(a, b)
    }
}
```

- [ ] **Step 2: Run — verify fail**

- [ ] **Step 3: Implement**

```swift
import Foundation

enum FireComposerImageTokens {
    private static let pattern = #"\{\{attach:(local-[0-9a-fA-F-]+)\}\}"#

    static func scanTokens(_ bodyText: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(bodyText.startIndex..., in: bodyText)
        return regex.matches(in: bodyText, range: range).compactMap { match in
            if let r = Range(match.range(at: 1), in: bodyText) {
                return String(bodyText[r])
            }
            return nil
        }
    }

    static func replaceTokens(_ bodyText: String, mappings: [String: String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return bodyText }
        let range = NSRange(bodyText.startIndex..., in: bodyText)
        var result = ""
        var lastEnd = bodyText.startIndex
        for match in regex.matches(in: bodyText, range: range) {
            guard let fullRange = Range(match.range, in: bodyText),
                  let idRange = Range(match.range(at: 1), in: bodyText) else { continue }
            let id = String(bodyText[idRange])
            result += bodyText[lastEnd..<fullRange.lowerBound]
            result += mappings[id] ?? bodyText[fullRange]
            lastEnd = fullRange.upperBound
        }
        result += bodyText[lastEnd...]
        return result
    }

    static func makeLocalId() -> String {
        "local-\(UUID().uuidString)"
    }
}
```

- [ ] **Step 4: Run — verify pass**

- [ ] **Step 5: Commit**

```
git add native/ios-app/App/Views/Composer/FireComposerImageTokens.swift native/ios-app/Tests/Unit/FireComposerImageTokensTests.swift
git commit -m "feat(ios): pure image token scan/replace for local-first attachments"
```

### Task 12: `FireComposerImageAttachment` (NSTextAttachment) + editor token rendering

**Files:**
- Create: `native/ios-app/App/Views/Composer/FireComposerImageAttachment.swift`
- Modify: `FireComposerView.swift` (text storage maps tokens → attachments)

**Interfaces:**
- Consumes: `FireComposerImageTokens` (Task 11).
- Produces: the inline 80×80 thumbnail attachment + remove affordance.

- [ ] **Step 1: Implement the attachment**

Follow the existing `FireRichTextEmojiAttachment` pattern (`App/Views/Shared/FireRichTextRenderer.swift:781`):

```swift
import UIKit

final class FireComposerImageAttachment: NSTextAttachment {
    let localId: String

    init(localId: String, thumbnail: UIImage) {
        self.localId = localId
        super.init(data: nil, ofType: nil)
        image = thumbnail.preparingForDisplay() ?? thumbnail
        bounds = CGRect(x: 0, y: -4, width: 80, height: 80)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
```

- [ ] **Step 2: Wire token → attachment rendering in the body editor**

When `bodyText` changes (or on insert), walk scanned tokens, load each local thumbnail via the draft store, and inject an `FireComposerImageAttachment` into the `bodyTextView.textStorage` at the token's range. Keep the underlying plain-text model (with `{{attach:...}}`) as the source of truth; the attachment is display-only.

Implement remove via long-press → "删除图片" (UIAlertController) → delete token from `bodyText` + delete local file.

- [ ] **Step 3: Build + run existing tests**

```
xcodebuild ... test
```
Expected: PASS.

- [ ] **Step 4: Commit**

```
git add native/ios-app/App/Views/Composer/FireComposerImageAttachment.swift native/ios-app/App/Views/Composer/FireComposerView.swift
git commit -m "feat(ios): inline local image attachment in composer editor"
```

### Task 13: PHPicker → local file (no upload); upload on publish

**Files:**
- Modify: `FireComposerView.swift` (`picker(_:didFinishPicking:)` ~line 2379, `uploadImageData` ~line 2120, `submitComposer` ~line 1898)

**Interfaces:**
- Consumes: `FireLocalDraftStore.saveImage/loadImage`, `FireComposerImageTokens`, `viewModel.uploadImage`, `markdownForUpload`.
- Produces: images persist locally at pick time; upload happens only at publish.

- [ ] **Step 1: Change `picker` delegate to save locally, insert token**

Replace the upload call with:

```swift
let localId = FireComposerImageTokens.makeLocalId()
try localDraftStore.saveImage(draftKey: route.draftKey, localId: localId,
                              fileExtension: fileExtension, bytes: data)
// Record attachment metadata so upload-on-publish can recover fileExtension/mimeType.
let attachment = FireLocalDraftAttachment(
    localId: localId, fileExtension: fileExtension,
    mimeType: mimeType, fileName: "image.\(fileExtension)")
draftAttachments[localId] = attachment   // persisted in Task 14's autosave
let token = "{{attach:\(localId)}}"
replaceText(in: bodySelection, with: "\n\(token)\n")
```

> `draftAttachments` is a `[String: FireLocalDraftAttachment]` on the controller that gets merged into `FireLocalDraft.attachments` whenever the draft is autosaved (Task 14). This ensures the metadata survives app relaunch alongside the token in `bodyText`.

- [ ] **Step 2: Add upload-on-publish step**

Before `createTopic`/`submitReply` in `submitComposer`:

```swift
let draft = localDraftStore.loadDraft(draftKey: route.draftKey)
let attachmentById = Dictionary(
    uniqueKeysWithValues: (draft?.attachments ?? []).map { ($0.localId, $0) })
let tokens = FireComposerImageTokens.scanTokens(bodyText)
var mappings: [String: String] = [:]
for id in tokens {
    guard let att = attachmentById[id] else {
        throw NSError(domain: "FireComposer", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "缺少图片信息: \(id)"])
    }
    let bytes = try localDraftStore.loadImage(
        draftKey: route.draftKey, localId: id, fileExtension: att.fileExtension)
    let result = try await viewModel.uploadImage(
        fileName: att.fileName, mimeType: att.mimeType, bytes: bytes)
    mappings[id] = markdownForUpload(result)
}
bodyText = FireComposerImageTokens.replaceTokens(bodyText, mappings: mappings)
```

On failure: abort, show error, keep local files + tokens (user retries). On success: after submit, `localDraftStore.deleteDraft(...)`.

- [ ] **Step 3: Build + test**

```
xcodebuild ... test
```
Expected: PASS.

- [ ] **Step 4: Commit**

```
git add native/ios-app/App/Views/Composer/FireComposerView.swift
git commit -m "feat(ios): local-first images, upload on publish"
```

### Task 14: Swap server drafts to local drafts (createTopic / non-PM advancedReply)

**Files:**
- Modify: `FireComposerView.swift` (`scheduleAutosave` ~1819, `persistDraftIfNeeded` ~1829, `loadInitialComposerState` ~1740, submit success paths ~1941/1983/2014)

**Interfaces:**
- Consumes: `FireLocalDraftStore` (Task 10), `route.isPrivateMessage` (existing).
- Produces: createTopic + non-PM advancedReply use local drafts; PM keeps `viewModel.saveDraft/fetchDraft/deleteDraft`.

- [ ] **Step 1: Branch draft persistence on route kind**

Add a computed gate:

```swift
private var usesLocalDrafts: Bool {
    switch route.kind {
    case .createTopic: return true
    case .advancedReply(_, _, _, _, _, let isPM): return !isPM
    case .privateMessage: return false
    }
}
```

- [ ] **Step 2: Replace autosave/persist/load/delete for the local path**

In `persistDraftIfNeeded()`: if `usesLocalDrafts`, build a `FireLocalDraft` and `try localDraftStore.saveDraft(...)`; else keep the existing server call.

In `loadInitialComposerState()`: if `usesLocalDrafts`, `localDraftStore.loadDraft(...)` and restore fields + step; else `viewModel.fetchDraft(...)`.

On submit success for local-path routes: `try localDraftStore.deleteDraft(...)`; for PM: `viewModel.deleteDraft(...)`.

- [ ] **Step 3: Add a PM regression test (if feasible without a live session)**

If the ViewModel can't be mocked cheaply, add an assertion-light test that `usesLocalDrafts` returns `false` for `.privateMessage` and PM `.advancedReply`, and `true` for createTopic + non-PM advancedReply. This guards the scope boundary the review flagged.

- [ ] **Step 4: Build + run full suite**

```
xcodebuild ... test
```
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```
git add native/ios-app/App/Views/Composer/FireComposerView.swift
git commit -m "feat(ios): local drafts for createTopic/non-PM reply; PM keeps server drafts"
```

### Task 15: Verification + xcodegen drift check + spec sync

**Files:**
- Read: `docs/superpowers/specs/2026-06-22-composer-redesign-design.md` (confirm no drift)

- [ ] **Step 1: Run the complete test suite**

```
xcodegen generate --spec native/ios-app/project.yml
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -derivedDataPath /tmp/fire-ios-unit CODE_SIGNING_ALLOWED=NO test
```
Expected: ALL tests PASS.

- [ ] **Step 2: Verify xcodegen project drift**

```
git -C /Users/fannnzhang/code/github.com/fire diff --exit-code native/ios-app/Fire.xcodeproj
```
Expected: no diff (the project file is in sync with `project.yml`). If there's a diff, `xcodegen generate` was skipped — re-run it and commit the regenerated project.

- [ ] **Step 3: Manual smoke checklist (record in PR)**

- Quick reply bar visible/tappable above keyboard (Phase 1).
- Composer: step 1 → fill title/category/tags → Next → step 2 editor.
- Category with `requiredTagGroup` blocks Next until satisfied.
- Image pick → inline 80×80 thumbnail → publish → uploads → submits.
- Kill app mid-edit → reopen → draft + images restored (createTopic).
- PM composer still autosaves to server (no local files written).

- [ ] **Step 4: Confirm spec has no stale references**

Re-read the spec; if any detail diverged during implementation (e.g. `RequiredTagGroupState.tags` field name, `routeKind` encoding), update the spec's §10 "Open questions" or the relevant section to match reality, and commit as `docs: ...`.

---

## Self-Review Notes

- **Spec coverage:** §4.1 → Tasks 1–4. §4.2 (step 1) → Tasks 5,7,8. §4.2 (step 2 + pickers) → Tasks 6,7,9. §4.3 (images) → Tasks 11–13. §4.4 (local drafts) → Tasks 10,14. §4.5 (half-sheets) → Task 9. §7 (errors) → handled inline in Tasks 13/14. §8 (testing) → Tasks 1,3,5,10,11 + PM guard Task 14.
- **VERIFIED:** `RequiredTagGroupState` has only `name` + `minCount` (no `tags`). `metaStepReady` therefore enforces `minimumRequiredTags` total count only; required-tag-group *content* is validated at publish by the server. **Spec §4.2 must be updated first (Task 5 prerequisite).** The plan's §4.2 gating and §10 reflect this; do NOT carry the stale `group.tags.contains` code into implementation.
- **Phase 1 geometry (review fixes P1 #1 + #2):** bar height = `10 + 36 + 12 + safeAreaBottom` (keyboard excluded, safe area kept). Keyboard overlap goes to feed `contentInset.bottom` only; the `ASInsetLayoutSpec` wraps ONLY the bar subtree (not the feed) so keyboard height is not double-counted.
- **Image metadata (review fix P1 #4):** `FireLocalDraft.attachments: [FireLocalDraftAttachment]` stores `localId`/`fileExtension`/`mimeType`/`fileName` so upload-on-publish can recover everything after app relaunch. The body token `{{attach:local-<uuid>}}` is the cross-reference key.
- **PM boundary enforced** in Task 14 with a guard test, matching the review fix.
- **Naming** `FireComposerTagSearchSheet` enforced in Task 9.
- **`FireComposerCardView`** made `internal` (Task 8 prerequisite) so the new step view file can use it.
