import SwiftUI
import UIKit

@MainActor
final class FireFilteredTopicListViewModel: ObservableObject {
    typealias FetchFilteredTopics = @MainActor (TopicListQueryState) async throws -> TopicListState

    @Published var selectedKind: TopicListKindState = .latest
    @Published private(set) var rows: [FireTopicRowPresentation] = []
    @Published private(set) var nextPage: UInt32?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let fetchFilteredTopics: FetchFilteredTopics
    private let categorySlug: String?
    private let categoryId: UInt64?
    private let parentCategorySlug: String?
    private let tag: String?
    private var loadGeneration: UInt64 = 0

    init(
        appViewModel: FireAppViewModel,
        categorySlug: String?,
        categoryId: UInt64?,
        parentCategorySlug: String?,
        tag: String?
    ) {
        self.fetchFilteredTopics = { query in
            try await appViewModel.fetchFilteredTopicList(query: query)
        }
        self.categorySlug = categorySlug
        self.categoryId = categoryId
        self.parentCategorySlug = parentCategorySlug
        self.tag = tag
    }

    init(
        categorySlug: String?,
        categoryId: UInt64?,
        parentCategorySlug: String?,
        tag: String?,
        fetchFilteredTopics: @escaping FetchFilteredTopics
    ) {
        self.fetchFilteredTopics = fetchFilteredTopics
        self.categorySlug = categorySlug
        self.categoryId = categoryId
        self.parentCategorySlug = parentCategorySlug
        self.tag = tag
    }

    func loadIfNeeded() async {
        guard rows.isEmpty, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        await load(page: nil, reset: true)
    }

    func selectKind(_ kind: TopicListKindState) async {
        guard selectedKind != kind else { return }
        selectedKind = kind
        await load(page: nil, reset: true)
    }

    func loadMore() async {
        guard let nextPage else { return }
        guard !isLoading, !isLoadingMore else { return }
        await load(page: nextPage, reset: false)
    }

    private func load(page: UInt32?, reset: Bool) async {
        let requestKind = selectedKind
        let requestPage = reset ? nil : page
        loadGeneration &+= 1
        let generation = loadGeneration

        if reset {
            isLoading = true
            isLoadingMore = false
            nextPage = nil
        } else {
            guard !isLoading else { return }
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
            let response = try await fetchFilteredTopics(
                TopicListQueryState(
                    kind: requestKind,
                    page: requestPage,
                    topicIds: [],
                    order: nil,
                    ascending: nil,
                    categorySlug: categorySlug,
                    categoryId: categoryId,
                    parentCategorySlug: parentCategorySlug,
                    tag: tag,
                    additionalTags: [],
                    matchAllTags: false
                )
            )
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }

            if reset {
                rows = response.rows
            } else {
                rows = mergeRows(existing: rows, incoming: response.rows)
            }
            nextPage = response.nextPage
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }
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

struct FireFilteredTopicListView: View {
    @ObservedObject var viewModel: FireAppViewModel

    let title: String
    let categorySlug: String?
    let categoryId: UInt64?
    let parentCategorySlug: String?
    let tag: String?

    @StateObject private var listViewModel: FireFilteredTopicListViewModel
    @State private var copiedErrorMessage = false

    init(
        viewModel: FireAppViewModel,
        title: String,
        categorySlug: String?,
        categoryId: UInt64?,
        parentCategorySlug: String?,
        tag: String?
    ) {
        self.viewModel = viewModel
        self.title = title
        self.categorySlug = categorySlug
        self.categoryId = categoryId
        self.parentCategorySlug = parentCategorySlug
        self.tag = tag
        _listViewModel = StateObject(
            wrappedValue: FireFilteredTopicListViewModel(
                appViewModel: viewModel,
                categorySlug: categorySlug,
                categoryId: categoryId,
                parentCategorySlug: parentCategorySlug,
                tag: tag
            )
        )
    }

    var body: some View {
        List {
            kindSelectorSection

            if let errorMessage = listViewModel.errorMessage,
               listViewModel.hasLoadedOnce {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: copiedErrorMessage,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                            copiedErrorMessage = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.2))
                                copiedErrorMessage = false
                            }
                        },
                        onDismiss: {
                            listViewModel.errorMessage = nil
                        }
                    )
                }
            }

            if !listViewModel.hasLoadedOnce {
                if let errorMessage = listViewModel.errorMessage {
                    Section {
                        FireBlockingErrorState(
                            title: "列表加载失败",
                            message: errorMessage,
                            onRetry: {
                                Task {
                                    await listViewModel.refresh()
                                }
                            }
                        )
                    }
                } else {
                    loadingSection
                }
            } else if listViewModel.rows.isEmpty {
                emptySection
            } else {
                topicListSection
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await listViewModel.refresh()
        }
        .task {
            await listViewModel.loadIfNeeded()
        }
    }

    // MARK: - Kind Selector

    private var kindSelectorSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(TopicListKindState.orderedCases, id: \.self) { kind in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                Task {
                                    await listViewModel.selectKind(kind)
                                }
                            }
                        } label: {
                            Text(kind.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(
                                    listViewModel.selectedKind == kind ? Color.white : Color(.label)
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        listViewModel.selectedKind == kind
                                            ? FireTheme.accent
                                            : Color(.tertiarySystemFill)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Topic List

    private var topicListSection: some View {
        Section {
            if listViewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 8)
                    Spacer()
                }
            }

            ForEach(listViewModel.rows, id: \.topic.id) { topicRow in
                NavigationLink {
                    FireTopicDetailView(viewModel: viewModel, row: topicRow)
                } label: {
                    FireTopicRow(
                        row: topicRow,
                        category: viewModel.categoryPresentation(for: topicRow.topic.categoryId)
                    )
                }
            }

            if listViewModel.nextPage != nil {
                loadMoreRow
            }
        }
    }

    private var loadMoreRow: some View {
        Button {
            Task {
                await listViewModel.loadMore()
            }
        } label: {
            HStack {
                Spacer()
                if listViewModel.isLoadingMore {
                    ProgressView().controlSize(.small)
                } else {
                    Label("加载更多", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.accent)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .disabled(listViewModel.isLoading || listViewModel.isLoadingMore)
        .listRowSeparator(.hidden)
    }

    // MARK: - Loading & Empty

    private var loadingSection: some View {
        Section {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.quaternarySystemFill))
                            .frame(width: 100, height: 10)
                    }
                }
                .padding(.vertical, 6)
                .redacted(reason: .placeholder)
            }
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("暂无话题")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("刷新") {
                    Task { await listViewModel.refresh() }
                }
                .buttonStyle(.bordered)
                .tint(FireTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        .listRowSeparator(.hidden)
    }
}
