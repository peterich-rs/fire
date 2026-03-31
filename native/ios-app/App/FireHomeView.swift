import SwiftUI

struct FireHomeView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @Namespace private var feedSelectionNamespace

    private var sessionTitle: String {
        viewModel.session.readiness.canReadAuthenticatedApi
            ? viewModel.session.profileDisplayName
            : "Fire"
    }

    var body: some View {
        NavigationStack {
            List {
                feedSelectorSection

                if viewModel.isLoadingTopics && viewModel.topicRows.isEmpty {
                    loadingSection
                } else if viewModel.topicRows.isEmpty {
                    emptySection
                } else {
                    topicListSection
                }
            }
            .listStyle(.plain)
            .navigationTitle(sessionTitle)
            .refreshable {
                await refreshTopics()
            }
        }
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
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(
                                    viewModel.selectedTopicKind == kind
                                        ? Color.white
                                        : Color(.label)
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
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
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Topic List

    private var topicListSection: some View {
        Section {
            ForEach(viewModel.topicRows, id: \.topic.id) { topicRow in
                NavigationLink {
                    FireTopicDetailView(viewModel: viewModel, row: topicRow)
                } label: {
                    FireTopicRow(
                        row: topicRow,
                        category: viewModel.categoryPresentation(for: topicRow.topic.categoryId)
                    )
                }
            }

            if let _ = viewModel.nextTopicsPage {
                loadMoreRow
            }
        }
    }

    private var loadMoreRow: some View {
        Button {
            viewModel.loadMoreTopics()
        } label: {
            HStack {
                Spacer()

                if viewModel.isAppendingTopics {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("加载更多", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.accent)
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .disabled(viewModel.isLoadingTopics)
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
        viewModel.refreshTopics()
        try? await Task.sleep(for: .seconds(1))
    }
}
