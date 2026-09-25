import Foundation

@MainActor
final class FireSearchService {
    private let host: FireAppServiceHost

    init(host: FireAppServiceHost) {
        self.host = host
    }

    func search(
        query: String,
        typeFilter: SearchTypeFilterState?,
        page: UInt32? = nil
    ) async throws -> SearchResultState {
        let sessionStore = try await host.sessionStoreValue()
        return try await sessionStore.search(
            query: SearchQueryState(
                q: query,
                page: page,
                typeFilter: typeFilter
            )
        )
    }

    func searchTags(
        query: String?,
        filterForInput: Bool = false,
        limit: UInt32? = nil,
        categoryID: UInt64? = nil,
        selectedTags: [String] = []
    ) async throws -> TagSearchResultState {
        let sessionStore = try await host.sessionStoreValue()
        return try await sessionStore.searchTags(
            query: TagSearchQueryState(
                q: query,
                filterForInput: filterForInput,
                limit: limit,
                categoryId: categoryID,
                selectedTags: selectedTags
            )
        )
    }

    func searchUsers(
        term: String,
        includeGroups: Bool = true,
        limit: UInt32 = 6,
        topicID: UInt64? = nil,
        categoryID: UInt64? = nil
    ) async throws -> UserMentionResultState {
        let sessionStore = try await host.sessionStoreValue()
        return try await sessionStore.searchUsers(
            query: UserMentionQueryState(
                term: term,
                includeGroups: includeGroups,
                limit: limit,
                topicId: topicID,
                categoryId: categoryID
            )
        )
    }
}
