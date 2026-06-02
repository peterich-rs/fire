import SwiftUI

struct FireTagPickerSheet: View {
    @EnvironmentObject private var homeFeedStore: FireHomeFeedStore
    let viewModel: FireAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [TagSearchItemState] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var topTags: [String] {
        homeFeedStore.topTags
    }

    private var displayedTags: [String] {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !searchResults.isEmpty {
            return searchResults.map(\.name)
        }
        return topTags
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                selectedTagsBar

                List {
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    } else if displayedTags.isEmpty {
                        emptyRow
                    } else {
                        ForEach(displayedTags, id: \.self) { tag in
                            tagRow(tag)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "搜索标签…")
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
            .navigationTitle("添加标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Selected Tags Bar

    @ViewBuilder
    private var selectedTagsBar: some View {
        if !homeFeedStore.selectedHomeTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(homeFeedStore.selectedHomeTags, id: \.self) { tag in
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Tag Row

    private func tagRow(_ tag: String) -> some View {
        let isSelected = homeFeedStore.selectedHomeTags.contains(tag)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSelected {
                    homeFeedStore.removeHomeTag(tag)
                } else {
                    homeFeedStore.addHomeTag(tag)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? FireTheme.accent : FireTheme.subtleInk)
                    .frame(width: 18, height: 18)

                Text(tag)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FireTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty

    private var emptyRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "暂无热门标签" : "未找到匹配的标签")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowSeparator(.hidden)
    }

    // MARK: - Search

    private func performSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }

                let result = try await viewModel.searchTags(
                    query: trimmed,
                    filterForInput: true,
                    limit: 20,
                    categoryID: homeFeedStore.selectedHomeCategoryId,
                    selectedTags: homeFeedStore.selectedHomeTags
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    searchResults = result.results
                    isSearching = false
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
}
