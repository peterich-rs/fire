import SwiftUI

struct FireNotificationHistoryView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @State private var selectedRoute: FireAppRoute?

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
        .navigationDestination(item: $selectedRoute) { route in
            FireAppRouteDestinationView(viewModel: viewModel, route: route)
        }
        .task {
            await viewModel.loadNotificationFullPage(offset: nil)
        }
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

        selectedRoute = item.appRoute
    }
}
