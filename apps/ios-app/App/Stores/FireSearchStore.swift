import Foundation

@MainActor
final class FireSearchStore: FirePaginatedStore<SearchResultState> {
    @Published var query = ""
    @Published private(set) var scope: FireSearchScope = .all

    private let appViewModel: FireAppViewModel
    private var activeSearchQuery = ""
    private var activeSearchScope: FireSearchScope = .all
    private var latestCompletedPage: UInt32 = 1

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    var result: SearchResultState? {
        items.first
    }

    var currentPage: UInt32 {
        latestCompletedPage
    }

    var isSearching: Bool {
        isLoading
    }

    var isAppending: Bool {
        isLoadingMore
    }

    var errorMessage: String? {
        blockingErrorMessage ?? nonBlockingErrorMessage
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

    func prepareSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }
        self.query = trimmedQuery
        submit(reset: true)
    }

    func submit(reset: Bool) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clear(resetQuery: false)
            return
        }

        activeSearchQuery = trimmedQuery
        activeSearchScope = scope

        if reset || result == nil {
            super.load(forceRefresh: true)
        } else {
            super.loadMore()
        }
    }

    override func fetchPage(offset: UInt32?) async throws -> PageResult {
        let page = offset ?? 1
        let response = try await appViewModel.searchService.search(
            query: activeSearchQuery,
            typeFilter: activeSearchScope.typeFilter,
            page: page
        )
        let hasMore = Self.canLoadMoreResults(in: response, scope: activeSearchScope)
        return PageResult(
            items: [response],
            nextOffset: hasMore ? page + 1 : nil,
            loadedOffset: page
        )
    }

    override func applyPage(_ result: PageResult, reset: Bool) {
        super.applyPage(result, reset: reset)
        latestCompletedPage = result.loadedOffset ?? 1
    }

    override func mergeItems(
        existing: [SearchResultState],
        incoming: [SearchResultState]
    ) -> [SearchResultState] {
        guard let next = incoming.first else {
            return existing
        }
        return [Self.merge(existing: existing.first, incoming: next)]
    }

    override func handlePageLoadError(_ error: Error, offset: UInt32?) async -> Bool {
        if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
            clearErrors()
            return true
        }
        return false
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
        super.reset()
        if resetQuery {
            query = ""
        }
        activeSearchQuery = ""
        activeSearchScope = .all
        latestCompletedPage = 1
        scope = .all
    }

    private nonisolated static func canLoadMoreResults(
        in result: SearchResultState,
        scope: FireSearchScope
    ) -> Bool {
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
}
