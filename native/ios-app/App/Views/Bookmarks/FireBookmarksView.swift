import Combine
import Foundation

enum FireBookmarksCollectionSection: Int, Hashable {
    case content
}

struct FireBookmarkRowID: Hashable {
    let value: String
}

enum FireBookmarksCollectionItem: Hashable {
    case blockingError(String)
    case inlineErrorBanner(String)
    case loading
    case empty
    case bookmark(FireBookmarkRowID)
    case loadingMore
}

@MainActor
final class FireBookmarksViewModel: ObservableObject {
    @Published private(set) var rows: [FireTopicRowPresentation] = []
    @Published private(set) var nextPage: UInt32?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let appViewModel: FireAppViewModel
    private let username: String

    init(appViewModel: FireAppViewModel, username: String) {
        self.appViewModel = appViewModel
        self.username = username
    }

    var lastRowID: FireBookmarkRowID? {
        rows.last.map(Self.rowID(for:))
    }

    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let list = try await appViewModel.fetchBookmarks(username: username, page: nil)
            rows = list.rows
            nextPage = list.nextPage
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentRowID: FireBookmarkRowID) async {
        guard !isLoadingMore else { return }
        guard let nextPage else { return }
        guard lastRowID == currentRowID else { return }

        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let list = try await appViewModel.fetchBookmarks(username: username, page: nextPage)
            rows = mergeRows(existing: rows, incoming: list.rows)
            self.nextPage = list.nextPage
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergeRows(
        existing: [FireTopicRowPresentation],
        incoming: [FireTopicRowPresentation]
    ) -> [FireTopicRowPresentation] {
        var merged = existing
        let existingIDs = Set(existing.map(Self.rowID(for:)))
        merged.append(contentsOf: incoming.filter { !existingIDs.contains(Self.rowID(for: $0)) })
        return merged
    }

    func row(for id: FireBookmarkRowID) -> FireTopicRowPresentation? {
        rows.first { Self.rowID(for: $0) == id }
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    func reportError(_ message: String) {
        errorMessage = message
    }

    static func rowID(for row: FireTopicRowPresentation) -> FireBookmarkRowID {
        if let bookmarkID = row.topic.bookmarkId {
            return FireBookmarkRowID(value: "bookmark:\(bookmarkID)")
        }

        let postNumber = row.topic.bookmarkedPostNumber ?? row.topic.lastReadPostNumber ?? 0
        return FireBookmarkRowID(value: "topic:\(row.topic.id):post:\(postNumber)")
    }
}
