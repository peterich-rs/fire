# iOS ListKit Home Migration

This note records the first W3 migration slice on `refactor/ios-store-split`:
the authenticated home feed now runs on the new collection-host ListKit
foundation instead of SwiftUI `List`.

## Scope

- add reusable collection-host primitives under `native/ios-app/App/ListKit/`
- keep SwiftUI navigation / sheets / toolbar ownership in `FireHomeView`
- move the home feed's hot-path list rendering into
  `native/ios-app/App/ListKit/Home/FireHomeCollectionView.swift`
- preserve existing home behavior:
  - feed/category/tag filtering
  - pull-to-refresh
  - pagination prefetch near the bottom
  - "fill viewport" auto-prefetch when the first page is short
  - topic navigation into `FireTopicDetailView`

This slice does not yet migrate notifications/history or topic detail to
collection-backed hosts.

## Runtime Shape

- `FireHomeView` now owns:
  - navigation destinations
  - create-topic / category / tag sheet presentation
  - top-level pagination coordination from collection scroll metrics
- `FireHomeCollectionView` now owns:
  - diffable section/item modeling for the home screen
  - home row rendering through `FireTopicRow`
  - content-state switching across:
    - filters chrome
    - loading skeletons
    - empty state
    - topic rows
    - append-loading footer
- `FireHomeFeedStore` remains the source of truth for:
  - selected filters
  - topic ordering and entities
  - home bootstrap metadata
  - refresh / append loading state

## ListKit Foundation

The new shared ListKit layer currently provides:

- `FireCollectionHost`
  - SwiftUI wrapper around a generic collection-backed controller
- `FireDiffableListController`
  - diffable snapshot apply
  - top-visible-item + relative-offset preservation across updates
  - visible-item publication
  - scroll-metrics publication
  - native `UIRefreshControl` bridge
- `FireListSectionModel`
  - minimal typed section/item container shared by future migrations

The controller intentionally stays generic and small so later W3 screens can
reuse it without inheriting home-specific behavior.

## Behavior Notes

- The home feed no longer depends on SwiftUI `List` row lifecycle for legacy
  pagination prefetch.
- Pagination now keys off collection scroll metrics for all supported OS
  versions.
- Topic row selection is collection-driven, but topic-detail navigation still
  resolves through SwiftUI `NavigationStack`.
- Snapshot updates preserve the user's top visible item instead of jumping
  back to the start when home rows patch after refresh.

## Verification

Verified on this branch with:

- `xcodegen generate --spec native/ios-app/project.yml`
- `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -derivedDataPath /tmp/fire-ios-w3-home CODE_SIGNING_ALLOWED=NO test`

That run covers:

- unit tests
- the W3 UI smoke target (`FireUITests`)
- app launch after the home-feed collection migration
