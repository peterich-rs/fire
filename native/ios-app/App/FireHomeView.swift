import SwiftUI

struct FireHomeView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @Namespace private var feedSelectionNamespace
    @State private var showCategoryBrowser = false
    @State private var showTagPicker = false
    @State private var showCreateTopicComposer = false
    @State private var didPrefetchToFillViewport = false

    private struct TopicListScrollMetrics: Equatable {
        let remainingDistanceToBottom: CGFloat
        let contentHeight: CGFloat
        let visibleHeight: CGFloat
    }

    private var parentCategories: [FireTopicCategoryPresentation] {
        viewModel.allCategories().filter { $0.parentCategoryId == nil }
    }

    var body: some View {
        NavigationStack {
            homeList
        }
    }

    @ViewBuilder
    private var homeList: some View {
        if #available(iOS 18.0, *) {
            baseList
                .onScrollGeometryChange(
                    for: TopicListScrollMetrics.self,
                    of: topicListScrollMetrics(from:)
                ) { oldValue, newValue in
                    handleTopicListScrollMetricsChange(oldValue: oldValue, newValue: newValue)
                }
        } else {
            baseList
        }
    }

    private var baseList: some View {
        List {
            categoryTabSection
            feedSelectorSection
            tagChipsSection

            if viewModel.isLoadingTopics && viewModel.topicRows.isEmpty {
                loadingSection
            } else if viewModel.topicRows.isEmpty {
                emptySection
            } else {
                topicListSection
            }
        }
        .listStyle(.plain)
        .navigationTitle("首页")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showCreateTopicComposer = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }

                    NavigationLink {
                        FireSearchView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
        .refreshable {
            didPrefetchToFillViewport = false
            await refreshTopics()
        }
        .onChange(of: viewModel.selectedTopicKind) { _, _ in
            didPrefetchToFillViewport = false
        }
        .onChange(of: viewModel.selectedHomeCategoryId) { _, _ in
            didPrefetchToFillViewport = false
        }
        .onChange(of: viewModel.selectedHomeTags) { _, _ in
            didPrefetchToFillViewport = false
        }
        .sheet(isPresented: $showCategoryBrowser) {
            FireCategoryBrowserSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showTagPicker) {
            FireTagPickerSheet(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showCreateTopicComposer) {
            NavigationStack {
                FireComposerView(
                    viewModel: viewModel,
                    route: FireComposerRoute(kind: .createTopic),
                    initialCategoryID: viewModel.selectedHomeCategoryId,
                    initialTags: viewModel.selectedHomeTags,
                    onTopicCreated: { _ in
                        showCreateTopicComposer = false
                    }
                )
            }
        }
    }

    // MARK: - Category Tabs

    private var categoryTabSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryTab(label: "全部", categoryId: nil, color: FireTheme.accent)

                    ForEach(parentCategories, id: \.id) { category in
                        categoryTab(
                            label: category.displayName,
                            categoryId: category.id,
                            color: Color(fireHex: category.colorHex) ?? FireTheme.accent
                        )
                    }

                    Button {
                        showCategoryBrowser = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FireTheme.subtleInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func categoryTab(label: String, categoryId: UInt64?, color: Color) -> some View {
        let isSelected = viewModel.selectedHomeCategoryId == categoryId
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectHomeCategory(categoryId)
            }
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color(.label))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? color : Color(.tertiarySystemFill))
                )
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed Selector

    private var feedSelectorSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(TopicListKindState.orderedCases, id: \.self) { kind in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectTopicKind(kind)
                            }
                        } label: {
                            Text(kind.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(
                                    viewModel.selectedTopicKind == kind
                                        ? Color.white
                                        : Color(.secondaryLabel)
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(
                                            viewModel.selectedTopicKind == kind
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
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Tag Chips

    @ViewBuilder
    private var tagChipsSection: some View {
        if !viewModel.selectedHomeTags.isEmpty || !viewModel.topTags().isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.selectedHomeTags, id: \.self) { tag in
                            selectedTagChip(tag)
                        }

                        Button {
                            showTagPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.caption2.weight(.bold))
                                Text("标签")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(FireTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .strokeBorder(FireTheme.accent.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private func selectedTagChip(_ tag: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.removeHomeTag(tag)
            }
        } label: {
            HStack(spacing: 4) {
                Text("#\(tag)")
                    .font(.caption.weight(.medium))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(FireTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(FireTheme.accent.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Topic List

    private static let paginationPrefetchDistance: CGFloat = 480
    private static let legacyPaginationPrefetchThreshold = 5

    private var topicListSection: some View {
        Section {
            ForEach(Array(viewModel.topicRows.enumerated()), id: \.element.topic.id) { index, topicRow in
                NavigationLink {
                    FireTopicDetailView(viewModel: viewModel, row: topicRow)
                } label: {
                    FireTopicRow(
                        row: topicRow,
                        category: viewModel.categoryPresentation(for: topicRow.topic.categoryId)
                    )
                }
                .onAppear {
                    if #unavailable(iOS 18.0) {
                        prefetchLegacyTopicsPageIfNeeded(currentIndex: index)
                    }
                }
            }

            if viewModel.nextTopicsPage != nil && viewModel.isAppendingTopics {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }
        }
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

                Text("当前 feed 暂无话题")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("刷新") {
                    viewModel.refreshTopics()
                }
                .buttonStyle(.bordered)
                .tint(FireTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        .listRowSeparator(.hidden)
    }

    // MARK: - Helpers

    @Sendable
    private func refreshTopics() async {
        await viewModel.refreshTopicsAsync()
    }

    @available(iOS 18.0, *)
    private func topicListScrollMetrics(from geometry: ScrollGeometry) -> TopicListScrollMetrics {
        TopicListScrollMetrics(
            remainingDistanceToBottom: max(0, geometry.contentSize.height - geometry.visibleRect.maxY),
            contentHeight: geometry.contentSize.height,
            visibleHeight: geometry.visibleRect.height
        )
    }

    private func handleTopicListScrollMetricsChange(
        oldValue: TopicListScrollMetrics,
        newValue: TopicListScrollMetrics
    ) {
        guard viewModel.nextTopicsPage != nil else { return }
        guard !viewModel.isLoadingTopics else { return }

        let contentFitsViewport = newValue.contentHeight <= newValue.visibleHeight + 1
        if contentFitsViewport && !didPrefetchToFillViewport {
            didPrefetchToFillViewport = true
            viewModel.loadMoreTopics()
            return
        }

        guard oldValue.remainingDistanceToBottom > Self.paginationPrefetchDistance else { return }
        guard newValue.remainingDistanceToBottom <= Self.paginationPrefetchDistance else { return }
        viewModel.loadMoreTopics()
    }

    private func prefetchLegacyTopicsPageIfNeeded(currentIndex: Int) {
        guard viewModel.nextTopicsPage != nil else { return }
        guard !viewModel.isLoadingTopics else { return }
        let triggerIndex = max(0, viewModel.topicRows.count - Self.legacyPaginationPrefetchThreshold)
        guard currentIndex >= triggerIndex else { return }
        viewModel.loadMoreTopics()
    }
}
