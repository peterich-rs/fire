import Foundation

@MainActor
final class FireSearchStore: ObservableObject {
    @Published var query = ""
    @Published private(set) var scope: FireSearchScope = .all
    @Published private(set) var result: SearchResultState?
    @Published private(set) var currentPage: UInt32 = 1
    @Published private(set) var isSearching = false
    @Published private(set) var isAppending = false
    @Published private(set) var errorMessage: String?

    private let appViewModel: FireAppViewModel
    private var searchTask: Task<Void, Never>?
    private var latestSearchRequestID: UInt64 = 0

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    var canLoadMoreResults: Bool {
        guard let result else { return false }
        switch scope {
        case .all:
            return result.groupedResult.moreFullPageResults
                || result.groupedResult.morePosts
                || result.groupedResult.moreUsers
        case .topic, .post:
            return result.groupedResult.moreFullPageResults
                || result.groupedResult.morePosts
        case .user:
            return result.groupedResult.moreUsers
        }
    }

    func reset(resetQuery: Bool = true) {
        clear(resetQuery: resetQuery)
    }

    func setScope(_ newScope: FireSearchScope) {
        guard scope != newScope else {
            return
        }
        scope = newScope
        guard result != nil else {
            return
        }
        submit(reset: true)
    }

    func submit(reset: Bool) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clear(resetQuery: false)
            return
        }
        if !reset && (isSearching || isAppending) {
            return
        }

        searchTask?.cancel()
        let nextPage = reset ? UInt32(1) : currentPage + 1
        let requestID = latestSearchRequestID &+ 1
        latestSearchRequestID = requestID
        let currentScope = scope

        if reset {
            isSearching = true
            isAppending = false
        } else {
            isAppending = true
        }

        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await self.appViewModel.search(
                    query: trimmedQuery,
                    typeFilter: currentScope.typeFilter,
                    page: nextPage
                )
                guard !Task.isCancelled, requestID == self.latestSearchRequestID else {
                    return
                }

                self.errorMessage = nil
                self.currentPage = nextPage
                self.result = reset
                    ? response
                    : Self.merge(existing: self.result, incoming: response)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, requestID == self.latestSearchRequestID else {
                    return
                }
                if await self.appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                    self.errorMessage = nil
                } else {
                    self.errorMessage = error.localizedDescription
                }
            }

            guard requestID == self.latestSearchRequestID else {
                return
            }
            self.isSearching = false
            self.isAppending = false
            self.searchTask = nil
        }
    }

    nonisolated static func merge(
        existing: SearchResultState?,
        incoming: SearchResultState
    ) -> SearchResultState {
        guard let existing else {
            return incoming
        }

        return SearchResultState(
            posts: mergeItemsByID(existing.posts, incoming.posts, keyPath: \.id),
            topics: mergeItemsByID(existing.topics, incoming.topics, keyPath: \.id),
            users: mergeItemsByID(existing.users, incoming.users, keyPath: \.id),
            groupedResult: incoming.groupedResult
        )
    }

    private nonisolated static func mergeItemsByID<Item>(
        _ existing: [Item],
        _ incoming: [Item],
        keyPath: KeyPath<Item, UInt64>
    ) -> [Item] {
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0[keyPath: keyPath], $0) })
        var orderedIDs = existing.map { $0[keyPath: keyPath] }

        for item in incoming {
            let id = item[keyPath: keyPath]
            if merged[id] == nil {
                orderedIDs.append(id)
            }
            merged[id] = item
        }

        return orderedIDs.compactMap { merged[$0] }
    }

    private func clear(resetQuery: Bool) {
        searchTask?.cancel()
        searchTask = nil
        latestSearchRequestID = latestSearchRequestID &+ 1
        if resetQuery {
            query = ""
        }
        result = nil
        currentPage = 1
        isSearching = false
        isAppending = false
        errorMessage = nil
        scope = .all
    }
}
