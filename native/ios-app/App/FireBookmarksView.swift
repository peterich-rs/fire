import SwiftUI
import UIKit

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

    static func rowID(for row: FireTopicRowPresentation) -> FireBookmarkRowID {
        if let bookmarkID = row.topic.bookmarkId {
            return FireBookmarkRowID(value: "bookmark:\(bookmarkID)")
        }

        let postNumber = row.topic.bookmarkedPostNumber ?? row.topic.lastReadPostNumber ?? 0
        return FireBookmarkRowID(value: "topic:\(row.topic.id):post:\(postNumber)")
    }
}

struct FireBookmarksView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let username: String

    @StateObject private var bookmarksViewModel: FireBookmarksViewModel
    @State private var editingContext: FireBookmarkEditorContext?
    @State private var selectedRoute: FireAppRoute?
    @Namespace private var pushTransitionNamespace

    private struct ContentVersion: Hashable {
        let rows: [FireTopicRowPresentation]
        let nextPage: UInt32?
        let isLoading: Bool
        let isLoadingMore: Bool
        let hasLoadedOnce: Bool
        let errorMessage: String?
    }

    init(viewModel: FireAppViewModel, username: String) {
        self.viewModel = viewModel
        self.username = username
        _bookmarksViewModel = StateObject(
            wrappedValue: FireBookmarksViewModel(appViewModel: viewModel, username: username)
        )
    }

    private var contentVersion: ContentVersion {
        ContentVersion(
            rows: bookmarksViewModel.rows,
            nextPage: bookmarksViewModel.nextPage,
            isLoading: bookmarksViewModel.isLoading,
            isLoadingMore: bookmarksViewModel.isLoadingMore,
            hasLoadedOnce: bookmarksViewModel.hasLoadedOnce,
            errorMessage: bookmarksViewModel.errorMessage
        )
    }

    private var sections: [FireListSectionModel<FireBookmarksCollectionSection, FireBookmarksCollectionItem>] {
        var items: [FireBookmarksCollectionItem] = []

        if let errorMessage = bookmarksViewModel.errorMessage,
           bookmarksViewModel.hasLoadedOnce {
            items.append(.inlineErrorBanner(errorMessage))
        }

        if !bookmarksViewModel.hasLoadedOnce {
            if let errorMessage = bookmarksViewModel.errorMessage {
                items.append(.blockingError(errorMessage))
            } else {
                items.append(.loading)
            }
        } else if bookmarksViewModel.rows.isEmpty {
            items.append(.empty)
        } else {
            items.append(contentsOf: bookmarksViewModel.rows.map {
                .bookmark(FireBookmarksViewModel.rowID(for: $0))
            })

            if bookmarksViewModel.isLoadingMore {
                items.append(.loadingMore)
            }
        }

        return [.init(id: .content, items: items)]
    }

    var body: some View {
        FireCollectionHost(
            sections: sections,
            contentVersion: contentVersion,
            itemContentToken: itemContentToken(for:),
            backgroundColor: .systemBackground,
            animatingDifferences: true,
            onSelectItem: handleSelection(_:),
            canSelectItem: canSelect(_:),
            onVisibleItemsChanged: handleVisibleItemsChanged(_:),
            onPrefetchItems: handlePrefetchItems(_:),
            onRefresh: {
                await bookmarksViewModel.refresh()
            },
            makeLayout: Self.makeLayout,
            rowContent: rowView(for:)
        )
        .navigationTitle("我的书签")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRoute) { route in
            FireAppRouteDestinationView(viewModel: viewModel, route: route)
                .fireNavigationPush(
                    sourceID: route.id,
                    namespace: pushTransitionNamespace
                )
        }
        .task {
            await bookmarksViewModel.loadIfNeeded()
        }
        .sheet(item: $editingContext) { context in
            FireBookmarkEditorSheet(
                context: context,
                onSave: { name, reminderAt in
                    guard let bookmarkID = context.bookmarkID else { return }
                    try await viewModel.updateBookmark(
                        bookmarkID: bookmarkID,
                        name: name,
                        reminderAt: reminderAt
                    )
                    await bookmarksViewModel.refresh()
                },
                onDelete: context.bookmarkID.map { bookmarkID in
                    {
                        try await viewModel.deleteBookmark(bookmarkID: bookmarkID)
                        await bookmarksViewModel.refresh()
                    }
                }
            )
        }
    }

    private static func makeLayout() -> UICollectionViewLayout {
        FireCollectionLayouts.plainList()
    }

    private func canSelect(_ item: FireBookmarksCollectionItem) -> Bool {
        if case .bookmark = item {
            return true
        }
        return false
    }

    private func handleSelection(_ item: FireBookmarksCollectionItem) {
        guard case let .bookmark(id) = item,
              let row = bookmarksViewModel.row(for: id) else { return }
        selectedRoute = .topic(
            row: row,
            postNumber: row.topic.bookmarkedPostNumber ?? row.topic.lastReadPostNumber
        )
    }

    private func handleVisibleItemsChanged(_ items: [FireBookmarksCollectionItem]) {
        loadMoreIfNeeded(from: items)
    }

    private func handlePrefetchItems(_ items: [FireBookmarksCollectionItem]) {
        loadMoreIfNeeded(from: items)
    }

    private func loadMoreIfNeeded(from items: [FireBookmarksCollectionItem]) {
        guard let lastRowID = bookmarksViewModel.lastRowID else { return }
        guard items.contains(.bookmark(lastRowID)) || items.contains(.loadingMore) else { return }
        Task {
            await bookmarksViewModel.loadMoreIfNeeded(currentRowID: lastRowID)
        }
    }

    private func itemContentToken(for item: FireBookmarksCollectionItem) -> AnyHashable {
        switch item {
        case let .blockingError(message), let .inlineErrorBanner(message):
            return AnyHashable(message)
        case .loading:
            return AnyHashable(bookmarksViewModel.isLoading)
        case .empty:
            return AnyHashable(bookmarksViewModel.hasLoadedOnce)
        case let .bookmark(id):
            guard let row = bookmarksViewModel.row(for: id) else {
                return AnyHashable("missing|\(id.value)")
            }
            return AnyHashable(bookmarkRowContentToken(row))
        case .loadingMore:
            return AnyHashable(bookmarksViewModel.isLoadingMore)
        }
    }

    @ViewBuilder
    private func rowView(for item: FireBookmarksCollectionItem) -> some View {
        switch item {
        case let .blockingError(message):
            FireBlockingErrorState(
                title: "书签加载失败",
                message: message,
                onRetry: {
                    Task {
                        await bookmarksViewModel.refresh()
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        case let .inlineErrorBanner(message):
            FireErrorBanner(
                message: message,
                copied: false,
                onCopy: {
                    UIPasteboard.general.string = message
                },
                onDismiss: {
                    bookmarksViewModel.errorMessage = nil
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, 28)
                Spacer()
            }
            .padding(.horizontal, 16)
        case .empty:
            VStack(spacing: 12) {
                Image(systemName: "bookmark")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(FireTheme.tertiaryInk)
                Text("还没有书签")
                    .font(.headline)
                    .foregroundStyle(FireTheme.ink)
                Text("把想回看的话题或帖子收进来，后续会统一在这里管理。")
                    .font(.subheadline)
                    .foregroundStyle(FireTheme.subtleInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
        case let .bookmark(id):
            if let row = bookmarksViewModel.row(for: id) {
                bookmarkRow(row)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .matchedTransitionSourceIfAvailable(
                        id: FireAppRoute.topic(
                            row: row,
                            postNumber: row.topic.bookmarkedPostNumber ?? row.topic.lastReadPostNumber
                        ).id,
                        in: pushTransitionNamespace
                    )
            } else {
                Color.clear.frame(height: 0)
            }
        case .loadingMore:
            HStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 10)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    private func bookmarkRowContentToken(_ row: FireTopicRowPresentation) -> String {
        let topic = row.topic
        let category = viewModel.categoryPresentation(for: topic.categoryId)
        var parts: [String] = []
        parts.reserveCapacity(31)
        parts.append(String(topic.id))
        parts.append(topic.title)
        parts.append(topic.slug)
        parts.append(String(topic.postsCount))
        parts.append(String(topic.replyCount))
        parts.append(String(topic.views))
        parts.append(String(topic.likeCount))
        parts.append(topic.excerpt ?? "")
        parts.append(topic.createdAt ?? "")
        parts.append(topic.lastPostedAt ?? "")
        parts.append(topic.lastPosterUsername ?? "")
        parts.append(topic.categoryId.map(String.init) ?? "")
        parts.append(String(topic.pinned))
        parts.append(String(topic.closed))
        parts.append(String(topic.archived))
        parts.append(String(topic.unseen))
        parts.append(String(topic.unreadPosts))
        parts.append(String(topic.newPosts))
        parts.append(topic.lastReadPostNumber.map(String.init) ?? "")
        parts.append(String(topic.highestPostNumber))
        parts.append(topic.bookmarkedPostNumber.map(String.init) ?? "")
        parts.append(topic.bookmarkId.map(String.init) ?? "")
        parts.append(topic.bookmarkName ?? "")
        parts.append(topic.bookmarkReminderAt ?? "")
        parts.append(topic.bookmarkableType ?? "")
        parts.append(row.excerptText ?? "")
        parts.append(row.originalPosterUsername ?? "")
        parts.append(row.originalPosterAvatarTemplate ?? "")
        parts.append(row.tagNames.joined(separator: ","))
        parts.append(row.statusLabels.joined(separator: ","))
        parts.append(category.map { "\($0.id)|\($0.displayName)|\($0.colorHex ?? "")" } ?? "")
        return parts.joined(separator: "\u{1F}")
    }

    private func bookmarkRow(_ row: FireTopicRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasBookmarkMeta(row) || row.topic.bookmarkId != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(spacing: 8) {
                        if let bookmarkName = row.topic.bookmarkName, !bookmarkName.isEmpty {
                            Label(bookmarkName, systemImage: "bookmark")
                                .font(.caption.weight(.medium))
                        }

                        if let reminderAt = row.topic.bookmarkReminderAt,
                           let reminderText = FireTopicPresentation.compactTimestamp(reminderAt) {
                            Label(reminderText, systemImage: "alarm")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(FireTheme.subtleInk)

                    Spacer(minLength: 8)

                    if row.topic.bookmarkId != nil {
                        Menu {
                            Button {
                                editingContext = editorContext(for: row)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                Task {
                                    await deleteBookmark(for: row)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FireTheme.tertiaryInk)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 6)
            }

            FireTopicRow(
                row: row,
                category: viewModel.categoryPresentation(for: row.topic.categoryId)
            )
        }
    }

    private func hasBookmarkMeta(_ row: FireTopicRowPresentation) -> Bool {
        row.topic.bookmarkName != nil || row.topic.bookmarkReminderAt != nil
    }

    private func editorContext(for row: FireTopicRowPresentation) -> FireBookmarkEditorContext {
        FireBookmarkEditorContext(
            bookmarkID: row.topic.bookmarkId,
            bookmarkableID: row.topic.id,
            bookmarkableType: row.topic.bookmarkableType ?? "Topic",
            title: row.topic.title,
            initialName: row.topic.bookmarkName,
            initialReminderAt: row.topic.bookmarkReminderAt,
            allowsDelete: row.topic.bookmarkId != nil
        )
    }

    private func deleteBookmark(for row: FireTopicRowPresentation) async {
        guard let bookmarkID = row.topic.bookmarkId else { return }
        do {
            try await viewModel.deleteBookmark(bookmarkID: bookmarkID)
            await bookmarksViewModel.refresh()
        } catch {
            bookmarksViewModel.errorMessage = error.localizedDescription
        }
    }
}
