import SwiftUI
import UIKit

private enum FireHomeCollectionSection: Int, Hashable {
    case categoryTabs
    case feedSelector
    case tagChips
    case content
}

private enum FireHomeCollectionItem: Hashable {
    case categoryTabs
    case feedSelector
    case tagChips
    case topic(UInt64)
    case loadingSkeleton(Int)
    case emptyState
    case appendingFooter
}

struct FireHomeCollectionView: View {
    @EnvironmentObject private var homeFeedStore: FireHomeFeedStore

    private struct FireHomeCollectionContentVersion: Hashable {
        let allCategories: [FireTopicCategoryPresentation]
        let topTags: [String]
        let selectedTopicKind: TopicListKindState
        let selectedHomeCategoryId: UInt64?
        let selectedHomeTags: [String]
        let topicRows: [FireTopicRowPresentation]
        let nextTopicsPage: UInt32?
        let isLoadingTopics: Bool
        let isAppendingTopics: Bool
    }

    let onShowCategoryBrowser: () -> Void
    let onShowTagPicker: () -> Void
    let onSelectTopic: (FireAppRoute) -> Void
    let onRefresh: () async -> Void
    let onScrollMetricsChanged: (FireCollectionScrollMetrics) -> Void

    private var parentCategories: [FireTopicCategoryPresentation] {
        homeFeedStore.allCategories.filter { $0.parentCategoryId == nil }
    }

    private var contentVersion: FireHomeCollectionContentVersion {
        FireHomeCollectionContentVersion(
            allCategories: homeFeedStore.allCategories,
            topTags: homeFeedStore.topTags,
            selectedTopicKind: homeFeedStore.selectedTopicKind,
            selectedHomeCategoryId: homeFeedStore.selectedHomeCategoryId,
            selectedHomeTags: homeFeedStore.selectedHomeTags,
            topicRows: homeFeedStore.topicRows,
            nextTopicsPage: homeFeedStore.nextTopicsPage,
            isLoadingTopics: homeFeedStore.isLoadingTopics,
            isAppendingTopics: homeFeedStore.isAppendingTopics
        )
    }

    private var sections: [FireListSectionModel<FireHomeCollectionSection, FireHomeCollectionItem>] {
        var sections: [FireListSectionModel<FireHomeCollectionSection, FireHomeCollectionItem>] = [
            .init(id: .categoryTabs, items: [.categoryTabs]),
            .init(id: .feedSelector, items: [.feedSelector]),
        ]

        if !homeFeedStore.selectedHomeTags.isEmpty || !homeFeedStore.topTags.isEmpty {
            sections.append(.init(id: .tagChips, items: [.tagChips]))
        }

        let contentItems: [FireHomeCollectionItem]
        if homeFeedStore.isLoadingTopics && homeFeedStore.topicRows.isEmpty {
            contentItems = (0..<6).map(FireHomeCollectionItem.loadingSkeleton)
        } else if homeFeedStore.topicRows.isEmpty {
            contentItems = [.emptyState]
        } else {
            contentItems =
                homeFeedStore.topicRows.map { .topic($0.topic.id) }
                + (homeFeedStore.nextTopicsPage != nil && homeFeedStore.isAppendingTopics
                    ? [.appendingFooter]
                    : [])
        }

        sections.append(.init(id: .content, items: contentItems))
        return sections
    }

    var body: some View {
        FireCollectionHost(
            sections: sections,
            contentVersion: contentVersion,
            backgroundColor: .systemBackground,
            animatingDifferences: true,
            onSelectItem: handleSelection(_:),
            canSelectItem: canSelect(_:),
            onVisibleItemsChanged: handleVisibleItemsChanged(_:),
            onScrollMetricsChanged: onScrollMetricsChanged,
            onRefresh: onRefresh,
            makeLayout: Self.makeLayout,
            rowContent: rowView(for:)
        )
    }

    private static func makeLayout() -> UICollectionViewLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = false
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private func canSelect(_ item: FireHomeCollectionItem) -> Bool {
        if case .topic = item {
            return true
        }
        return false
    }

    private func handleSelection(_ item: FireHomeCollectionItem) {
        guard case let .topic(topicID) = item,
              let row = homeFeedStore.topicRow(for: topicID) else { return }
        onSelectTopic(.topic(row: row))
    }

    private func handleVisibleItemsChanged(_ items: [FireHomeCollectionItem]) {
        let visibleTopicIDs: Set<UInt64> = Set(items.compactMap { item in
            guard case let .topic(topicID) = item else { return nil }
            return topicID
        })
        homeFeedStore.updateVisibleTopicIDs(visibleTopicIDs)
    }

    @ViewBuilder
    private func rowView(for item: FireHomeCollectionItem) -> some View {
        switch item {
        case .categoryTabs:
            categoryTabsRow
        case .feedSelector:
            feedSelectorRow
        case .tagChips:
            tagChipsRow
        case let .topic(topicID):
            if let row = homeFeedStore.topicRow(for: topicID) {
                FireTopicRow(
                    row: row,
                    category: homeFeedStore.categoryPresentation(for: row.topic.categoryId)
                )
                .padding(.horizontal, 16)
            } else {
                Color.clear
                    .frame(height: 0)
            }
        case .loadingSkeleton:
            loadingRow
        case .emptyState:
            emptyStateRow
        case .appendingFooter:
            appendingFooterRow
        }
    }

    private var categoryTabsRow: some View {
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

                Button(action: onShowCategoryBrowser) {
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
        .padding(.top, 8)
        .padding(.bottom, 4)
        .padding(.horizontal, 16)
    }

    private func categoryTab(label: String, categoryId: UInt64?, color: Color) -> some View {
        let isSelected = homeFeedStore.selectedHomeCategoryId == categoryId
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                homeFeedStore.selectHomeCategory(categoryId)
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

    private var feedSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(TopicListKindState.orderedCases, id: \.self) { kind in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            homeFeedStore.selectTopicKind(kind)
                        }
                    } label: {
                        Text(kind.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(
                                homeFeedStore.selectedTopicKind == kind
                                    ? Color.white
                                    : Color(.secondaryLabel)
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(
                                        homeFeedStore.selectedTopicKind == kind
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
        .padding(.top, 2)
        .padding(.bottom, 4)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var tagChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button(action: onShowTagPicker) {
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

                ForEach(homeFeedStore.selectedHomeTags, id: \.self) { tag in
                    selectedTagChip(tag)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
        .padding(.horizontal, 16)
    }

    private func selectedTagChip(_ tag: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                homeFeedStore.removeHomeTag(tag)
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

    private var loadingRow: some View {
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
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
    }

    private var emptyStateRow: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.secondary)

            Text("当前 feed 暂无话题")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("刷新") {
                homeFeedStore.refreshTopics()
            }
            .buttonStyle(.bordered)
            .tint(FireTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 40)
    }

    private var appendingFooterRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
