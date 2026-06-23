# Composer & Quick Reply Redesign

**Date**: 2026-06-22
**Scope**: iOS — topic detail quick reply bar, new-topic composer, advanced reply composer. Private message composer is out of scope.

## 1. Problem

### 1.1 Quick reply bar (topic detail) — broken layout

`FireTopicQuickReplyBarNode` is overlaid on the feed via `ASRelativeLayoutSpec(verticalPosition: .end)`. Its `measuredHeight` formula is `10 + 36 + 12 + bottomInset`, where `bottomInset` is the **full keyboard height**. When the keyboard rises:

1. The bar grows to `input row + full keyboard height`.
2. It is pinned to the overlay's bottom edge (view bottom).
3. The input row ends up behind/below the keyboard → invisible, untappable.

Root cause: the bar absorbs the keyboard inset into its own height instead of letting the collection's `contentInset.bottom` absorb it so content scrolls up to reveal the bar.

### 1.2 Composer (new topic / advanced reply) — poor overall experience

- **No keyboard avoidance.** Only `scrollView.keyboardDismissMode = .interactive` is set. `bottomBar` is pinned to `view.bottomAnchor`; submit button, validation label, and markdown toolbar are covered by the keyboard.
- **Information overload.** Title, category, tag chips, suggested tags, tag field, markdown toolbar, editor, mention results, body requirement, preview — all stacked in one scroll view at once.
- **No guided flow.** No progressive disclosure; user doesn't know what's missing until submit validation fires.
- **Rough visual feel.** Dense layout, unclear hierarchy, doesn't feel like a place you'd want to write in.
- **Image UX is bad.** Selecting a photo immediately uploads it via `POST /uploads.json`, then inserts `![alt|WxH](upload://xxx)` markdown into the body. The editor is a plain `UITextView` so the user sees raw markdown text, not a preview. If upload fails, the flow breaks.
- **Drafts are server-only.** `DraftDataState` is persisted via Discourse's server draft API. Local images cannot be part of a draft because there's no upload URL yet.

## 2. Goals

1. Fix quick reply bar so it is always visible and tappable above the keyboard.
2. Redesign the composer into a two-step flow: step 1 (title + category + tags), step 2 (editor-centric body with markdown toolbar floating above keyboard).
3. Make images local-first: pick → local thumbnail preview in editor → upload on publish.
4. Move drafts to local storage so images survive across sessions without needing server upload.
5. Advanced reply skips step 1, enters step 2 directly with a reply-context header instead of title/category card.

## 3. Non-goals

- Private message composer changes (current UX is acceptable per user).
- Rich-text / WYSIWYG rendering of markdown in the editor body. The body editor remains a plain `UITextView`; only image attachments get inline visual treatment via `NSTextAttachment`.
- Android composer (iOS-only in this spec).
- Changes to the server draft API or Discourse upload protocol.

## 4. Design

### 4.1 Quick reply bar fix

**Bar height excludes keyboard inset.** The bar only owns `input row (36) + vertical padding (22) + safe-area bottom`. The keyboard inset is applied to the feed's `contentInset.bottom` so feed content scrolls up to reveal the bar.

```
FireTopicQuickReplyBarNode.estimatedHeight:
  height = 10 + 36 + 12   // input row + padding only
  + topStackHeight (typing/target, conditional)
  + validationMessageHeight (conditional)
  // bottomInset (keyboard) is NOT added here

FireTopicDetailRootNode.layout():
  insets.bottom = barHeight + keyboardInset  // feed contentInset
  // bar is positioned at view.bottom - keyboardInset - safeArea
```

**Bar vertical position.** The overlay layout must offset the bar up by the keyboard height so it sits above the keyboard. This is done by constraining the bar node's bottom to `view.bottomAnchor - currentBottomChromeInset` instead of growing the bar's height.

This is a bug fix within the existing Texture node path. No fallback rendering introduced.

### 4.2 Composer two-step flow

#### Step 1: Title + Category + Tags

A single screen. State-driven: category selection controls whether the tag section appears.

**Initial state (no category selected):**

```
┌─────────────────────────────────┐
│  ←            新建话题            │
│                                 │
│  说了什么？                      │
│  ┌标题─────────────────────┐    │
│  │ 输入标题…                │    │
│  └─────────────────────────┘    │
│                                 │
│  发到哪个版块？                   │
│  ┌────────────────────────┐     │
│  │ ○ 开发调优              │     │  ← hot categories (inline chips/list)
│  │ ○ 资源分享              │     │     tap to select directly
│  │ ○ 站务公告              │     │
│  │ ○ 求助问答              │     │
│  │ 更多分类…            →  │     │  ← opens half-sheet panel (full list)
│  └────────────────────────┘     │
│                                 │
│                         [下一步]│  ← disabled until title + category valid
└─────────────────────────────────┘
```

**Category selected (tag section appears, category list collapses to summary):**

```
│  发到哪个版块？
│  ┌已选分类──────────────────┐
│  │ ● 资源分享        更换 ▾  │   ← tap "更换" to re-open list/panel
│  └──────────────────────────┘
│
│  添加标签（至少 2 个）
│  ┌已选标签──────────────────┐
│  │ #分享 ×  #教程 ×          │
│  └──────────────────────────┘
│  ┌热门标签──────────────────┐
│  │ #分享  #教程  #资源       │   ← from allowedTags + topTags, deduped
│  │ #推荐  #原创  #转载       │
│  └──────────────────────────┘
│  没有想要的？搜索标签          →   ← collapsed; tap to expand search field
│
│                    [下一步 →]     ← enabled when title + category + min tags met
```

**Tag data sources:**
- Hot tags: `category.allowedTags` (when non-empty) merged with `viewModel.topTags()`, deduped, capped at ~8.
- Tag search: `searchService.searchTags(query, filterForInput: true, categoryID: selectedCategory)` — only shown when user expands the collapsed search entry.

**Category selection interaction:**
- Inline hot categories: filtered to `permission <= 1`, sorted by display name, top ~4 shown. Tap selects directly.
- "更多分类…" opens a half-sheet panel (`sheetPresentationController`, detents `[.medium(), .large()]`) with the full sorted list, each row showing display name + requirement summary (min tags, template indicator).
- "更换" on the selected-category summary re-opens the same panel (or inline list).

**Category change clears tags.** If the user changes category while tags are selected, show a confirm alert: "更换分类会清空已选标签，继续？". On confirm, clear `selectedTags` and re-render. Rationale: `allowedTags` differ across categories; clearing is predictable and simple.

**Next button gating:** enabled when `trimmedTitle.count >= minimumTitleLength` AND `selectedCategoryID != nil` AND `selectedTags.count >= selectedCategoryMinimumTags`. If the category has no minimum tag requirement, tags are optional.

**Category template injection:** if the selected category has a `topicTemplate`, inject it into the body when transitioning to step 2 (only if body is empty). Track `lastInjectedTemplate` so re-selecting the same category doesn't overwrite user edits.

#### Step 2: Editor-centric body

```
┌─────────────────────────────────┐
│  ←    编辑正文          [预览][发布]│
├─────────────────────────────────┤
│  回复 @xxx                       │  ← advanced reply only; omitted for createTopic
│  ┌分类·标签────────────── 收起 ▾┐ │  ← createTopic only; collapsed summary
│  │ 资源分享 · #分享 #教程  修改  │ │     tap to re-open category/tag panel
│  └─────────────────────────────┘ │
│                                 │
│  ┌正文编辑器（自适应高度）──────┐ │  ← main area, always visible
│  │                             │ │
│  │  在这里写下你的内容…          │ │
│  │                             │ │
│  │  ┌──────┐                   │ │  ← image attachment (NSTextAttachment)
│  │  │ 80x80│  ✕                │ │     local thumbnail, tap to enlarge
│  │  └──────┘                   │ │     ✕ to remove
│  │                             │ │
│  └─────────────────────────────┘ │
│                                 │
├─────────────────────────────────┤
│ [B I S <> ``` " • 1.a 🖼]  123字│  ← markdown toolbar, pinned above keyboard
├─────────────────────────────────┤
│ ▓▓▓ 键盘 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
└─────────────────────────────────┘
```

**Category/tag summary card (step 2, createTopic only):**
- Default collapsed, showing: `分类名 · #tag #tag`.
- Tap to expand: re-opens the category/tag panel (same half-sheet from step 1) or inline editor. Changes apply to the shared draft state.
- This lets the user fix tag/category issues discovered while writing without leaving step 2.

**Reply context header (step 2, advancedReply only):**
- Shows "回复 @username" or "回复 #postNumber".
- No title/category card.

**Markdown toolbar:**
- Pinned above the keyboard via `keyboardLayoutGuide`. Uses the existing `FireMarkdownFormatAction` set and `FireMarkdownInsertion` logic.
- Includes the image button (🖼) that opens `PHPickerViewController`.

**Character count:** `trimmedBody.count / minimumBodyLength+` shown right-aligned in the toolbar row.

**Keyboard avoidance:**
- `scrollView` bottom constrained to `keyboardLayoutGuide.topAnchor` (or equivalent notification-driven inset).
- Markdown toolbar and submit button ride above the keyboard.
- `scrollView.keyboardDismissMode = .interactive` retained for drag-to-dismiss.

**Preview mode:** toggles between editor and rendered preview (existing logic, reused). Preview shows title, category, tags, and rendered body with resolved image URLs.

#### Navigation between steps

- Step 1 → Step 2: "下一步" button (validated). Push or replace, animating transition.
- Step 2 → Step 1: back button (not close). Content preserved.
- Step 2 publish: "发布" button. Validates all fields, uploads images, submits.
- Close (either step): no confirmation; draft auto-saves locally. Close immediately.

**Implementation approach:** A single `FireComposerViewController` with a `step` state (`.meta` / `.body`) that swaps the content view. This keeps the shared draft state (`titleText`, `selectedCategoryID`, `selectedTags`, `bodyText`, `images`) in one place without cross-controller coordination. Navigation bar title changes per step.

#### Advanced reply entry

`FireComposerViewController` initialized with `route.kind == .advancedReply` starts directly at `.body` step. The `.meta` step is skipped entirely (no title, no category, no tags). The reply-context header replaces the category/tag card.

### 4.3 Image handling: local-first, upload on publish

#### Selection

`PHPickerViewController` (single image, `.images` filter). On pick:

1. Load image data (`loadDataRepresentation`).
2. Generate a local UUID: `local-<uuid>`.
3. Persist image data to `App Sandbox / Drafts / <draftKey> / local-<uuid>.<ext>`.
4. Generate an 80×80 thumbnail `UIImage` for inline display.
5. Insert placeholder token `{{attach:local-<uuid>}}` into `bodyText` at cursor position.
6. Render the placeholder as an `NSTextAttachment` in `bodyTextView` showing the thumbnail + a remove (✕) button overlay.

No network call at selection time.

#### Inline display

`bodyTextView` is a `UITextView`. Image placeholders are rendered via `NSTextAttachment` subclasses:

- `FireComposerImageAttachment`: holds the local thumbnail `UIImage` (80×80) and the `localId`.
- The attachment's bounds are set to `CGRect(0, 0, 80, 80)` so it displays as a compact inline block, not disrupting text flow.
- Tapping the attachment opens a full-screen preview (`FireTopicPhotoBrowserController` or equivalent).
- A small ✕ overlay is rendered via the attachment's image or a tap-and-hold → "删除图片" action. Removing the attachment deletes the `{{attach:local-id}}` token from `bodyText` and the local file.

The body text model remains plain text containing `{{attach:local-<uuid>}}` tokens. The `UITextView` text storage maps these tokens to `FireComposerImageAttachment` for display via `NSTextStorageDelegate` / custom layout. On save/restore, the plain-text form with tokens is what gets persisted.

#### Upload on publish

Before calling `viewModel.createTopic` / `viewModel.submitReply`:

1. Scan `bodyText` for all `{{attach:local-<uuid>}}` tokens.
2. For each, read the local file, call `viewModel.uploadImage(fileName:mimeType:bytes:)` → `UploadResultState`.
3. Replace the token with the Discourse markdown: `![alt|WxH](upload://shortUrl)` (using `markdownForUpload` logic, already exists).
4. If any upload fails, abort submission with the error; local files and tokens are preserved so the user can retry.
5. After successful submission, delete local draft files.

Upload progress: show a loading state on the submit button ("上传图片中…" / "发布中…").

#### Draft persistence (images)

Local draft files in `Drafts / <draftKey> / local-<uuid>.<ext>` survive across sessions. On draft restore:

1. Load `bodyText` containing `{{attach:local-<uuid>}}` tokens.
2. For each token, check if the local file exists.
3. If yes, regenerate the thumbnail and `NSTextAttachment`.
4. If no (file was cleaned up), replace the token with empty string or a broken-image placeholder.

### 4.4 Local draft storage

**Pure local storage.** Replace server draft API calls with a local store. No more `viewModel.saveDraft` / `viewModel.fetchDraft` / `viewModel.deleteDraft` for composer state.

**Storage:** A lightweight local persistence layer (file-based JSON + image files). No new DB dependency (GRDB/SQLite/CoreData) — the data is small and simple.

```
App Support / FireDrafts /
  <draftKey>/
    meta.json          # title, categoryId, tags, bodyText, recipients, step, updatedAt
    local-<uuid>.jpg   # image files
```

**`meta.json` schema:**

```json
{
  "draftKey": "new_topic",
  "step": "body",
  "title": "...",
  "categoryId": 4,
  "tags": ["分享", "教程"],
  "bodyText": "正文 {{attach:local-abc123}} 更多",
  "recipients": [],
  "routeKind": "createTopic",
  "updatedAt": 1719043200.0
}
```

**API (new, iOS-only, replaces server draft calls in composer):**

```swift
protocol FireLocalDraftStore {
    func loadDraft(draftKey: String) -> FireLocalDraft?
    func saveDraft(draftKey: String, draft: FireLocalDraft)
    func deleteDraft(draftKey: String)
    func listDrafts() -> [FireLocalDraftSummary]
}

struct FireLocalDraft {
    var draftKey: String
    var step: ComposerStep
    var title: String
    var categoryId: UInt64?
    var tags: [String]
    var bodyText: String
    var recipients: [String]
    var routeKind: RouteKind
    var updatedAt: Date
}
```

**Autosave:** 1.2s debounce after last edit (matching existing behavior). Saves to local store.

**Draft lifecycle:**
- On composer open: load local draft for `route.draftKey`. If present, restore fields + images.
- On edit: autosave to local.
- On successful publish: delete local draft + image files.
- On close without publish: keep local draft (no confirmation needed for keeping; only confirm if user explicitly clears).

**Existing server draft code removal:** The composer's calls to `viewModel.saveDraft`, `viewModel.fetchDraft`, `viewModel.deleteDraft`, and `scheduleAutosave` (server variant) are replaced by local store calls. The server draft API and its UniFFI bindings remain available for other consumers but are no longer used by the composer.

**Note on `draftSequence`:** Server drafts use a sequence for conflict resolution. Local drafts are single-writer (one device, one composer instance), so no sequence is needed. `draftSequence` is removed from composer state.

### 4.5 Half-sheet panels

Two reusable half-sheet panel controllers:

1. **`FireCategoryPickerSheet`** — full category list with search. Used by "更多分类…" and "更换".
2. **`FireTagPickerSheet`** — tag search with results. Used by "没有想要的？搜索标签". (Hot tags remain inline in step 1; this sheet is only for search.)

Both use `sheetPresentationController` with detents `[.medium(), .large()]` and `prefersGrabberVisible = true`. Presented over the current step.

For step 2's category/tag card expand: re-present `FireCategoryPickerSheet` (category change clears tags as described above).

## 5. Component inventory

| Component | Type | Responsibility |
|-----------|------|----------------|
| `FireTopicQuickReplyBarNode` | Existing (Texture) | Fix height formula + keyboard offset |
| `FireTopicDetailRootNode` | Existing (Texture) | Fix bar positioning vs keyboard |
| `FireComposerViewController` | Existing (UIKit) | Add step state machine; restructure layout |
| `FireComposerMetaStepView` | New (UIKit) | Step 1 content: title, category, tags |
| `FireComposerBodyStepView` | New (UIKit) | Step 2 content: editor, toolbar, attachments |
| `FireCategoryPickerSheet` | New (UIKit) | Half-sheet category list + search |
| `FireTagPickerSheet` | New (UIKit) | Half-sheet tag search |
| `FireComposerImageAttachment` | New (NSTextAttachment) | Inline local image thumbnail in UITextView |
| `FireLocalDraftStore` | New (protocol + impl) | File-based local draft persistence |
| `FireLocalDraft` | New (struct) | Draft data model |

## 6. Data flow

```
Step 1 (meta)                         Step 2 (body)
┌──────────────┐                      ┌──────────────┐
│ titleText     │──┐                ┌──│ bodyText      │
│ categoryId    │  │                │  │ images[]      │
│ tags[]        │  ├── shared ──→   ├──│ (local files) │
└──────────────┘  │  FireLocalDraft │  └──────┬───────┘
                  │  (autosave)     │         │
                  └─────────────────┘         │ publish
                                              ↓
                                    1. upload images (POST /uploads.json)
                                    2. replace {{attach:id}} → ![..](upload://..)
                                    3. createTopic / submitReply
                                    4. delete local draft + files
```

## 7. Error handling

| Scenario | Behavior |
|----------|----------|
| Image upload fails on publish | Abort submission. Show error. Local files + tokens preserved. User can retry. |
| Local draft file missing on restore | Remove dangling `{{attach:id}}` token from body. Show notice "部分图片无法恢复". |
| Local draft save fails (disk full) | Show error banner. Continue editing (in-memory state preserved). |
| Category change clears tags | Confirm alert before clearing. |
| Submit validation fails | Highlight the missing field. If category/tags, offer to open the picker. If body length, scroll to editor. |
| Close with unsaved draft content | No confirmation (draft auto-saves locally). Close immediately. |

## 8. Testing

- **Unit:** `FireComposerValidation` (existing, extend for step transitions). `FireLocalDraftStore` (save/load/delete/restore with images). `FireMarkdownInsertion` (existing, verify `{{attach:}}` token handling). Image token scan + replacement logic (pure function, testable without UIKit).
- **Unit:** Quick reply bar height calculation (no keyboard inset in height). Root node inset calculation (keyboard inset in `contentInset.bottom`, not bar height).
- **Integration:** PHPicker → local file → attachment render → publish upload → markdown replacement → submit. End-to-end with mock upload service.
- **Manual:** Quick reply bar visible and tappable with keyboard up. Composer step 1 → step 2 transition. Image pick → preview → publish. Draft restore across app relaunch.

## 9. Phased implementation

**Phase 1 — Quick reply bar fix** (bug fix, ships independently)
- Fix `FireTopicQuickReplyBarNode.estimatedHeight` to exclude keyboard inset.
- Fix `FireTopicDetailRootNode` bar positioning vs keyboard.
- Verify feed scrolls to reveal bar.

**Phase 2 — Composer keyboard avoidance + layout restructure**
- Add `keyboardLayoutGuide`-driven avoidance.
- Introduce `step` state machine (`.meta` / `.body`).
- Build `FireComposerMetaStepView` (title + category inline + tags conditional).
- Restructure `FireComposerBodyStepView` (editor-centric, toolbar above keyboard).
- Category/tag half-sheet panels.

**Phase 3 — Image local-first + local drafts**
- `FireComposerImageAttachment` + token system.
- `FireLocalDraftStore` (file-based).
- Image pick → local file → preview → publish upload.
- Remove server draft API calls from composer.
- Draft restore with images.

Phase 1 is independently shippable. Phases 2 and 3 can be developed in sequence (3 depends on 2's step architecture for the body editor).

## 10. Open questions

None remaining. All design decisions confirmed with user.
