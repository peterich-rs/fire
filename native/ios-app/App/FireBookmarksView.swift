import SwiftUI
import UIKit

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

    func loadIfNeeded() async {
        guard rows.isEmpty else { return }
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

    func loadMoreIfNeeded(currentTopicID: UInt64) async {
        guard !isLoadingMore else { return }
        guard let nextPage else { return }
        guard rows.last?.topic.id == currentTopicID else { return }

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
        let existingIDs = Set(existing.map(\.topic.id))
        merged.append(contentsOf: incoming.filter { !existingIDs.contains($0.topic.id) })
        return merged
    }
}

struct FireBookmarksView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let username: String

    @StateObject private var bookmarksViewModel: FireBookmarksViewModel
    @State private var editingContext: FireBookmarkEditorContext?
    @State private var selectedRoute: FireAppRoute?
    @Namespace private var pushTransitionNamespace

    init(viewModel: FireAppViewModel, username: String) {
        self.viewModel = viewModel
        self.username = username
        _bookmarksViewModel = StateObject(
            wrappedValue: FireBookmarksViewModel(appViewModel: viewModel, username: username)
        )
    }

    var body: some View {
        List {
            if let errorMessage = bookmarksViewModel.errorMessage,
               bookmarksViewModel.hasLoadedOnce {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                        },
                        onDismiss: {
                            bookmarksViewModel.errorMessage = nil
                        }
                    )
                }
            }

            if !bookmarksViewModel.hasLoadedOnce {
                if let errorMessage = bookmarksViewModel.errorMessage {
                    Section {
                        FireBlockingErrorState(
                            title: "书签加载失败",
                            message: errorMessage,
                            onRetry: {
                                Task {
                                    await bookmarksViewModel.refresh()
                                }
                            }
                        )
                    }
                } else {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 24)
                            Spacer()
                        }
                    }
                }
            } else if bookmarksViewModel.rows.isEmpty {
                Section {
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
                    .padding(.vertical, 28)
                }
            } else {
                Section {
                    ForEach(bookmarksViewModel.rows, id: \.topic.id) { row in
                        Button {
                            selectedRoute = .topic(
                                row: row,
                                postNumber: row.topic.bookmarkedPostNumber ?? row.topic.lastReadPostNumber
                            )
                        } label: {
                            bookmarkRow(row)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSourceIfAvailable(
                            id: FireAppRoute.topic(
                                row: row,
                                postNumber: row.topic.bookmarkedPostNumber ?? row.topic.lastReadPostNumber
                            ).id,
                            in: pushTransitionNamespace
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if row.topic.bookmarkId != nil {
                                Button("编辑") {
                                    editingContext = editorContext(for: row)
                                }
                                .tint(FireTheme.accent)

                                Button("删除", role: .destructive) {
                                    Task {
                                        await deleteBookmark(for: row)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            Task {
                                await bookmarksViewModel.loadMoreIfNeeded(currentTopicID: row.topic.id)
                            }
                        }
                    }

                    if bookmarksViewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
        .refreshable {
            await bookmarksViewModel.refresh()
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

    private func bookmarkRow(_ row: FireTopicRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasBookmarkMeta(row) {
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
