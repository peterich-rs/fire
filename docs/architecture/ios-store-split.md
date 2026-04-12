# iOS Store Split

This note records the first W2 extraction after private-message closure.

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

## Follow-up order

The next W2 slices should keep the same pattern:

1. notification list/full-history state
2. home feed filters, pagination, and list refresh ownership
3. topic detail cache and presence/reaction lifecycle

Only after those slices are stable should `FireAppViewModel` shrink further
from "feature owner" to a mostly session-scoped coordinator.
