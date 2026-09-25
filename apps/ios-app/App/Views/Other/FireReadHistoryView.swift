import Combine
import Foundation

enum FireReadHistoryCollectionSection: Int, Hashable {
    case content
}

enum FireReadHistoryCollectionItem: Hashable {
    case blockingError(String)
    case inlineErrorBanner(String)
    case loading
    case empty
    case topic(UInt64)
    case loadingMore
}

@MainActor
final class FireReadHistoryViewModel: ObservableObject {
    @Published private(set) var rows: [FireTopicRowPresentation] = []
    @Published private(set) var nextPage: UInt32?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let appViewModel: FireAppViewModel

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    func loadIfNeeded() async {
        guard rows.isEmpty, !isLoading else { return }
        await load(page: nil, reset: true)
    }

    func refresh() async {
        await load(page: nil, reset: true)
    }

    func loadMoreIfNeeded(currentTopicID: UInt64) async {
        guard let nextPage else { return }
        guard !isLoading, !isLoadingMore else { return }
        guard rows.last?.topic.id == currentTopicID else { return }
        await load(page: nextPage, reset: false)
    }

    var lastTopicID: UInt64? {
        rows.last?.topic.id
    }

    func row(for topicID: UInt64) -> FireTopicRowPresentation? {
        rows.first { $0.topic.id == topicID }
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    func reportError(_ message: String) {
        errorMessage = message
    }

    private func load(page: UInt32?, reset: Bool) async {
        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let response = try await appViewModel.fetchReadHistory(page: page)
            if reset {
                rows = response.rows
            } else {
                rows = mergeRows(existing: rows, incoming: response.rows)
            }
            nextPage = response.nextPage
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergeRows(
        existing: [FireTopicRowPresentation],
        incoming: [FireTopicRowPresentation]
    ) -> [FireTopicRowPresentation] {
        var merged = existing
        let existingTopicIDs = Set(existing.map(\.topic.id))
        for row in incoming where !existingTopicIDs.contains(row.topic.id) {
            merged.append(row)
        }
        return merged
    }
}
