# iOS Store Split

This note records the early W2 extractions after private-message closure.

## Problem

`FireAppViewModel` currently owns session lifecycle plus home feed, topic
detail, notifications, search, diagnostics hooks, and write-side transient
state. That means isolated search input and pagination changes still emit
`objectWillChange` from the app-wide root object.

## First extraction

The first W2 slice moves search-screen state into
`native/ios-app/App/Stores/FireSearchStore.swift`.

`FireSearchStore` now owns:

- query text
- selected search scope
- current `SearchResultState`
- pagination cursor
- loading / append-loading flags
- search-screen error state

`FireAppViewModel` still owns:

- session bootstrap and authenticated-shell lifecycle
- `FireSessionStore` initialization and shared Rust API access
- recoverable auth handling (`LoginRequired`, Cloudflare challenge)
- helper request methods used by feature stores, such as `search`, `searchTags`,
  and `searchUsers`

## Why search first

- The boundary is narrow and screen-local.
- Search already has a dedicated screen.
- It reduces one of the largest unrelated invalidation sources without touching
  topic detail retention or MessageBus ownership yet.
- It establishes the transitional pattern for later W2 stores: feature state
  moves out first, while `FireAppViewModel` temporarily remains the shared
  session facade.

## Second extraction

The second W2 slice moves notification-screen state into
`native/ios-app/App/Stores/FireNotificationStore.swift`.

`FireNotificationStore` now owns:

- unread badge count
- recent notification list state
- full-history notification list state
- full-history paging cursor
- notification-specific loading flags
- delayed MessageBus/runtime notification refresh scheduling

`FireAppViewModel` still owns:

- MessageBus transport lifecycle itself
- notification API helper methods backed by `FireSessionStore`
- recoverable auth handling used by the store when notification requests fail

This keeps the badge and notification list churn off the app-wide root
`ObservableObject` while leaving the shared session/runtime ownership unchanged.

## Follow-up order

The next W2 slices should keep the same pattern:

1. home feed filters, pagination, and list refresh ownership
2. topic detail cache and presence/reaction lifecycle
3. any remaining tab/profile-local state that still lives on `FireAppViewModel`

Only after those slices are stable should `FireAppViewModel` shrink further
from "feature owner" to a mostly session-scoped coordinator.
