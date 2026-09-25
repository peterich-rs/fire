import Foundation

extension FireSessionStore {
    public func search(query: SearchQueryState) async throws -> SearchResultState {
        try await runPersistingSessionChanges {
            try await core.search().search(query: query)
        }
    }

    public func searchTags(query: TagSearchQueryState) async throws -> TagSearchResultState {
        try await runPersistingSessionChanges {
            try await core.search().searchTags(query: query)
        }
    }

    public func searchUsers(query: UserMentionQueryState) async throws -> UserMentionResultState {
        try await runPersistingSessionChanges {
            try await core.search().searchUsers(query: query)
        }
    }
}
