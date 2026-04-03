import SwiftUI

struct FireFilteredTopicListView: View {
    @ObservedObject var viewModel: FireAppViewModel

    let title: String
    let categorySlug: String?
    let categoryId: UInt64?
    let parentCategorySlug: String?
    let tag: String?

    @State private var selectedKind: TopicListKindState = .latest
    @State private var rows: [FireTopicRowPresentation] = []
    @State private var nextPage: UInt32?
    @State private var isLoading = false
    @State private var isAppending = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            kindSelectorSection

            if isLoading && rows.isEmpty {
                loadingSection
            } else if rows.isEmpty {
                emptySection
            } else {
                topicListSection
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadTopics(page: nil, reset: true)
        }
        .task {
            if rows.isEmpty {
                await loadTopics(page: nil, reset: true)
            }
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
                                guard selectedKind != kind else { return }
                                selectedKind = kind
                                rows = []
                                nextPage = nil
                                Task {
                                    await loadTopics(page: nil, reset: true)
                                }
                            }
                        } label: {
                            Text(kind.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(
                                    selectedKind == kind ? Color.white : Color(.label)
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        selectedKind == kind
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
            ForEach(rows, id: \.topic.id) { topicRow in
                NavigationLink {
                    FireTopicDetailView(viewModel: viewModel, row: topicRow)
                } label: {
                    FireTopicRow(
                        row: topicRow,
                        category: viewModel.categoryPresentation(for: topicRow.topic.categoryId)
                    )
                }
            }

            if nextPage != nil {
                loadMoreRow
            }
        }
    }

    private var loadMoreRow: some View {
        Button {
            guard let page = nextPage else { return }
            Task {
                await loadTopics(page: page, reset: false)
            }
        } label: {
            HStack {
                Spacer()
                if isAppending {
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
        .disabled(isLoading)
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
                Text(errorMessage ?? "暂无话题")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("刷新") {
                    Task { await loadTopics(page: nil, reset: true) }
                }
                .buttonStyle(.bordered)
                .tint(FireTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        .listRowSeparator(.hidden)
    }

    // MARK: - Data Loading

    private func loadTopics(page: UInt32?, reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        isAppending = !reset
        defer {
            isLoading = false
            isAppending = false
        }

        do {
            let query = TopicListQueryState(
                kind: selectedKind,
                page: page,
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
            let response = try await viewModel.fetchFilteredTopicList(query: query)
            if reset {
                rows = response.rows
            } else {
                let existingIDs = Set(rows.map(\.topic.id))
                let newRows = response.rows.filter { !existingIDs.contains($0.topic.id) }
                rows.append(contentsOf: newRows)
            }
            nextPage = response.nextPage
            errorMessage = nil
        } catch {
            if reset {
                rows = []
                nextPage = nil
            }
            errorMessage = error.localizedDescription
        }
    }
}
