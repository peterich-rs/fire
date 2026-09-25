import Combine
import SwiftUI
import UIKit

@MainActor
final class FirePrivateMessagesViewModel: ObservableObject {
    typealias FetchPrivateMessages = @MainActor (
        TopicListKindState,
        UInt32?
    ) async throws -> TopicListState

    @Published var selectedKind: TopicListKindState = .privateMessagesInbox
    @Published private(set) var rows: [TopicRowState] = []
    @Published private(set) var users: [TopicUserState] = []
    @Published private(set) var renderedKind: TopicListKindState?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let fetchPrivateMessages: FetchPrivateMessages
    private var nextPage: UInt32?
    private var hasMore = true
    private var loadGeneration: UInt64 = 0

    init(appViewModel: FireAppViewModel) {
        self.fetchPrivateMessages = { kind, page in
            try await appViewModel.fetchPrivateMessages(kind: kind, page: page)
        }
    }

    init(fetchPrivateMessages: @escaping FetchPrivateMessages) {
        self.fetchPrivateMessages = fetchPrivateMessages
    }

    var hasResolvedCurrentKind: Bool {
        renderedKind == selectedKind
    }

    var displayedRows: [TopicRowState] {
        hasResolvedCurrentKind ? rows : []
    }

    var displayedUsers: [TopicUserState] {
        hasResolvedCurrentKind ? users : []
    }

    var currentKindDisplayState: FireScopedTopicListDisplayState {
        FireScopedTopicListDisplayState.resolve(
            hasResolvedCurrentScope: hasResolvedCurrentKind,
            hasRows: !displayedRows.isEmpty,
            errorMessage: errorMessage
        )
    }

    private func deduplicatedRows(_ rows: [TopicRowState]) -> [TopicRowState] {
        var seenTopicIDs = Set<UInt64>()
        return rows.filter { row in
            seenTopicIDs.insert(row.topic.id).inserted
        }
    }

    private func deduplicatedUsers(_ users: [TopicUserState]) -> [TopicUserState] {
        var seenUserIDs = Set<UInt64>()
        return users.filter { user in
            seenUserIDs.insert(user.id).inserted
        }
    }

    func loadIfNeeded() async {
        guard (!hasResolvedCurrentKind || rows.isEmpty), !isLoading else { return }
        await load(reset: true)
    }

    func refresh() async {
        await load(reset: true)
    }

    func selectKind(_ kind: TopicListKindState) async {
        guard selectedKind != kind else { return }
        selectedKind = kind
        await load(reset: true)
    }

    func loadMoreIfNeeded(currentTopicID: UInt64) async {
        guard hasResolvedCurrentKind else { return }
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard displayedRows.last?.topic.id == currentTopicID else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        let requestKind = selectedKind
        let requestPage = reset ? nil : nextPage
        loadGeneration &+= 1
        let generation = loadGeneration

        if reset {
            isLoading = true
            isLoadingMore = false
            nextPage = nil
            hasMore = false
        } else {
            isLoadingMore = true
        }
        errorMessage = nil

        defer {
            if generation == loadGeneration {
                isLoading = false
                isLoadingMore = false
            }
        }

        do {
            let response = try await fetchPrivateMessages(requestKind, requestPage)
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }

            let uniqueRows = deduplicatedRows(response.rows)
            let uniqueUsers = deduplicatedUsers(response.users)
            let freshRows: [TopicRowState]
            let freshUsers: [TopicUserState]

            if reset {
                rows = uniqueRows
                users = uniqueUsers
                freshRows = uniqueRows
                freshUsers = uniqueUsers
            } else {
                let existingIDs = Set(rows.map(\.topic.id))
                freshRows = uniqueRows.filter { !existingIDs.contains($0.topic.id) }
                rows.append(contentsOf: freshRows)
                let existingUserIDs = Set(users.map(\.id))
                freshUsers = uniqueUsers.filter { !existingUserIDs.contains($0.id) }
                users.append(contentsOf: freshUsers)
            }

            let resolvedNextPage: UInt32? = {
                guard let candidate = response.nextPage else {
                    return nil
                }
                guard let requestPage else {
                    return candidate
                }
                return candidate > requestPage ? candidate : nil
            }()

            let receivedFreshContent = !freshRows.isEmpty || !freshUsers.isEmpty
            nextPage = resolvedNextPage
            hasMore = resolvedNextPage != nil && (reset || receivedFreshContent)
            renderedKind = requestKind
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}
