import SwiftUI

struct FireNotificationHistoryView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @State private var topicNavigation: FireHistoryTopicNavigation?
    @State private var deferredFeatureToast: String?

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var body: some View {
        Group {
            if viewModel.isLoadingNotificationFullPage && viewModel.notificationFullList.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.notificationFullList.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .navigationTitle("全部通知")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if viewModel.notificationUnreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("全部已读") {
                        viewModel.markAllNotificationsRead()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FireTheme.accent)
                }
            }
        }
        .refreshable {
            await viewModel.loadNotificationFullPage(offset: nil)
        }
        .navigationDestination(item: $topicNavigation) { nav in
            FireTopicDetailView(
                viewModel: viewModel,
                row: nav.row,
                scrollToPostNumber: nav.postNumber
            )
        }
        .task {
            await viewModel.loadNotificationFullPage(offset: nil)
        }
        .overlay(alignment: .bottom) {
            if let toast = deferredFeatureToast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color(.darkGray)))
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation { deferredFeatureToast = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: deferredFeatureToast)
    }

    private var notificationList: some View {
        List {
            ForEach(viewModel.notificationFullList, id: \.id) { item in
                Button {
                    handleNotificationTap(item)
                } label: {
                    FireNotificationRowContent(
                        item: item,
                        baseURLString: baseURLString
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if viewModel.hasMoreNotificationFull {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 16)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .task {
                    await viewModel.loadNotificationFullPage(
                        offset: viewModel.notificationFullNextOffset
                    )
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(FireTheme.tertiaryInk)

            Text("暂无通知")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("刷新") {
                Task {
                    await viewModel.loadNotificationFullPage(offset: nil)
                }
            }
            .buttonStyle(FireSecondaryButtonStyle())
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleNotificationTap(_ item: NotificationItemState) {
        if !item.read {
            viewModel.markNotificationRead(id: item.id)
        }

        switch item.tapDestination {
        case .topic(let topicId, let postNumber, let slug, let title):
            let row = TopicRowState.stub(
                topicId: topicId,
                title: title,
                slug: slug,
                categoryId: nil
            )
            topicNavigation = FireHistoryTopicNavigation(
                row: row,
                postNumber: postNumber
            )
        case .deferredProfile:
            withAnimation { deferredFeatureToast = "个人主页功能即将上线" }
        case .deferredBadge:
            withAnimation { deferredFeatureToast = "徽章详情功能即将上线" }
        case .noAction:
            break
        }
    }
}

private struct FireHistoryTopicNavigation: Identifiable, Hashable {
    let row: TopicRowState
    let postNumber: UInt32?

    var id: UInt64 { row.topic.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(row.topic.id)
        hasher.combine(postNumber)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row.topic.id == rhs.row.topic.id && lhs.postNumber == rhs.postNumber
    }
}
