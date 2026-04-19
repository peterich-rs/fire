# iOS Store Split

This note records the completed W2 store split on
`refactor/ios-store-split`.

## Outcome

`FireAppViewModel` no longer owns home-feed and topic-detail feature state.
The iOS host now follows a consistent split:

- `FireAppViewModel` is the session/runtime facade.
- screen-level feature state lives in dedicated stores.
- hot list state uses explicit entity indexing instead of implicit array-only
  replacement.

The root wiring now happens in `FireTabRoot`:

- `FireHomeFeedStore`
- `FireSearchStore`
- `FireNotificationStore`
- `FireTopicDetailStore`
- `FireProfileViewModel`

Home and topic detail consume their store state directly through environment
injection, while search and notifications continue to observe their existing
dedicated stores.

## Store Ownership

### `FireAppViewModel`

`FireAppViewModel` now retains only cross-cutting responsibilities:

- `SessionState` publication
- `FireSessionStore` initialization and access
- login / logout / Cloudflare recovery
- MessageBus transport lifecycle
- diagnostics and APM route coordination
- thin helper APIs used by stores and non-store screens

It binds feature stores but no longer publishes home-list or topic-detail
state itself.

### `FireHomeFeedStore`

`native/ios-app/App/Stores/FireHomeFeedStore.swift` owns:

- selected feed kind
- selected home category and tags
- home topic rows
- paging metadata (`moreTopicsUrl`, `nextTopicsPage`)
- category/tag bootstrap snapshots used by home/category/tag screens
- home loading / append-loading flags
- current-scope load error state used to distinguish blocking first-load failures from non-blocking refresh failures
- the scope snapshot for the rows currently rendered on screen
- topic-list MessageBus refresh debounce and incremental merge behavior

Home rows are backed internally by:

- `FireEntityIndex<UInt64, FireTopicRowPresentation>`
- `FireOrderedIDList<UInt64>`

That keeps entity patching and append order explicit while still exposing
materialized rows to SwiftUI.

### `FireTopicDetailStore`

`native/ios-app/App/Stores/FireTopicDetailStore.swift` owns:

- `TopicDetailState` cache by topic id
- anchor post numbers for routed detail loads
- active detail owner tokens
- post hydration / pagination state
- reply-presence users
- detail loading flags
- reply submission and post-mutation flags
- topic-detail MessageBus refresh scheduling

All detail-specific mutations now reconcile through this store:

- quick reply
- post edit refresh path
- like / unlike
- non-heart reaction toggles
- detail refresh after topic vote / poll vote / topic edit

### Existing W2 Stores

The earlier W2 slices remain unchanged in role:

- `FireSearchStore` owns query, scope, result state, pagination, and
  search-screen errors.
- `FireNotificationStore` owns unread count, recent/full notification state,
  first-load vs refresh error state for the recent list, paging, and delayed
  runtime refresh.

## Shared Primitives

Two small shared state helpers now back entity-first list management:

- `native/ios-app/App/Stores/Shared/FireEntityIndex.swift`
- `native/ios-app/App/Stores/Shared/FireOrderedIDList.swift`

They are intentionally minimal:

- `FireEntityIndex` replaces/upserts payloads by stable business id.
- `FireOrderedIDList` preserves first-seen order while deduplicating ids.

W2 uses them first on the home feed, which is the highest-churn list that
still needed stable incremental patching after search/notification extraction.

## Scoped Observation Changes

The following screens now observe feature stores instead of the app-wide root
object for their primary state:

- `FireHomeView`
- `FireCategoryBrowserSheet`
- `FireCategoriesView`
- `FireTagPickerSheet`
- `FireTopicDetailView`

This means:

- search input changes do not invalidate the home feed
- notification badge/list churn does not invalidate topic detail
- topic-detail post hydration and reaction changes do not invalidate the full
  tab root through `FireAppViewModel`

`FireAppViewModel` is still passed into many screens for session-aware helper
methods, but those screens no longer depend on it for the extracted feature
state.

## Verification

Verified on this branch with:

- `xcodegen generate --spec native/ios-app/project.yml`
- `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'id=EF568FD9-DF26-4B62-B7AB-7C66851CF3D9' -derivedDataPath /tmp/fire-ios-w2 CODE_SIGNING_ALLOWED=NO test`

The test run now includes the new entity-state coverage in
`native/ios-app/Tests/Unit/FireEntityStateTests.swift`.
