import SwiftUI
import UIKit

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

struct FireReadHistoryView: View {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter
    @ObservedObject var viewModel: FireAppViewModel
    @StateObject private var historyViewModel: FireReadHistoryViewModel
    @State private var selectedRoute: FireAppRoute?
    @State private var editingBookmarkContext: FireBookmarkEditorContext?
    @State private var topicActionNotice: String?
    @State private var toast: FireToast?

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
        _historyViewModel = StateObject(
            wrappedValue: FireReadHistoryViewModel(appViewModel: viewModel)
        )
    }

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var body: some View {
        List {
            if let errorMessage = historyViewModel.errorMessage,
               historyViewModel.hasLoadedOnce {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                        },
                        onDismiss: {
                            historyViewModel.errorMessage = nil
                        }
                    )
                }
            }

            if !historyViewModel.hasLoadedOnce {
                if let errorMessage = historyViewModel.errorMessage {
                    Section {
                        FireBlockingErrorState(
                            title: "浏览历史加载失败",
                            message: errorMessage,
                            onRetry: {
                                Task {
                                    await historyViewModel.refresh()
                                }
                            }
                        )
                    }
                } else {
                    Section {
                        FireTopicSkeletonList(rowCount: 6)
                    }
                }
            } else if historyViewModel.rows.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.title2)
                            .foregroundStyle(FireTheme.subtleInk)
                        Text("还没有浏览历史")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FireTheme.ink)
                        Text("看过的话题会在这里继续接上次读到的位置。")
                            .font(.caption)
                            .foregroundStyle(FireTheme.subtleInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                Section {
                    ForEach(historyViewModel.rows, id: \.topic.id) { row in
                        Button {
                            presentRoute(.topic(
                                row: row,
                                postNumber: row.topic.lastReadPostNumber
                            ))
                        } label: {
                            FireTopicRow(
                                row: row,
                                category: viewModel.categoryPresentation(for: row.topic.categoryId)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            FireTopicContextMenu(
                                row: row,
                                shareURL: row.fireTopicURL(baseURL: baseURLString),
                                onOpen: {
                                    presentRoute(.topic(
                                        row: row,
                                        postNumber: row.topic.lastReadPostNumber
                                    ))
                                },
                                onBookmark: {
                                    editingBookmarkContext = row.fireBookmarkEditorContext()
                                },
                                onMute: {
                                    muteTopic(row)
                                }
                            )
                        }
                        .task {
                            await historyViewModel.loadMoreIfNeeded(currentTopicID: row.topic.id)
                        }
                    }

                    if historyViewModel.isLoadingMore {
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
        .scrollContentBackground(.hidden)
        .background(FireTheme.canvasTop)
        .navigationTitle("浏览历史")
        .navigationBarTitleDisplayMode(.inline)
        .fireNavigationDestination(item: $selectedRoute) { route in
            FireAppRouteDestinationView(viewModel: viewModel, route: route)
        }
        .task {
            await historyViewModel.loadIfNeeded()
        }
        .refreshable {
            await historyViewModel.refresh()
        }
        .sheet(item: $editingBookmarkContext) { context in
            FireBookmarkEditorSheet(
                context: context,
                onSave: { name, reminderAt in
                    if let bookmarkID = context.bookmarkID {
                        try await viewModel.topicInteraction.updateBookmark(
                            bookmarkID: bookmarkID,
                            name: name,
                            reminderAt: reminderAt
                        )
                    } else {
                        _ = try await viewModel.topicInteraction.createBookmark(
                            bookmarkableID: context.bookmarkableID,
                            bookmarkableType: context.bookmarkableType,
                            name: name,
                            reminderAt: reminderAt
                        )
                    }
                    await historyViewModel.refresh()
                },
                onDelete: context.bookmarkID.map { bookmarkID in
                    {
                        try await viewModel.topicInteraction.deleteBookmark(bookmarkID: bookmarkID)
                        await historyViewModel.refresh()
                    }
                }
            )
        }
        .onChange(of: topicActionNotice) { message in
            guard let message,
                  !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            toast = FireToast(message: message, style: .error)
            topicActionNotice = nil
        }
        .fireToast($toast)
    }

    private func presentRoute(_ route: FireAppRoute) {
        if topicRoutePresenter.present(route) {
            return
        }
        selectedRoute = route
    }

    private func muteTopic(_ row: FireTopicRowPresentation) {
        Task {
            do {
                try await viewModel.topicInteraction.setTopicNotificationLevel(
                    topicID: row.topic.id,
                    notificationLevel: FireTopicNotificationLevelOption.muted.rawValue
                )
                toast = FireToast(message: "已静音话题", style: .success)
            } catch {
                topicActionNotice = error.localizedDescription
            }
        }
    }
}
