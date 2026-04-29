import SwiftUI
import UIKit

struct FireNotificationHistoryView: View {
    let appViewModel: FireAppViewModel
    @ObservedObject var notificationStore: FireNotificationStore
    @State private var selectedRoute: FireAppRoute?

    private var baseURLString: String {
        let trimmed = appViewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var body: some View {
        Group {
            if let errorMessage = notificationStore.blockingFullErrorMessage {
                blockingErrorState(message: errorMessage)
            } else if notificationStore.isLoadingFullPage && notificationStore.fullNotifications.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notificationStore.fullNotifications.isEmpty {
                emptyState(errorMessage: notificationStore.fullNonBlockingErrorMessage)
            } else {
                notificationList
            }
        }
        .navigationTitle("全部通知")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if notificationStore.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("全部已读") {
                        notificationStore.markAllRead()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FireTheme.accent)
                }
            }
        }
        .refreshable {
            await notificationStore.loadFullPage(offset: nil)
        }
        .navigationDestination(item: $selectedRoute) { route in
            FireAppRouteDestinationView(viewModel: appViewModel, route: route)
        }
        .task {
            await notificationStore.loadFullPage(offset: nil)
        }
    }

    private func retryFullLoad() {
        Task {
            await notificationStore.retryFullLoad()
        }
    }

    private func blockingErrorState(message: String) -> some View {
        FireBlockingErrorState(
            title: "全部通知加载失败",
            message: message,
            onRetry: retryFullLoad
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notificationList: some View {
        List {
            if let errorMessage = notificationStore.fullNonBlockingErrorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                        },
                        onDismiss: {
                            notificationStore.clearFullError()
                        }
                    )
                }
            }

            ForEach(notificationStore.fullNotifications, id: \.id) { item in
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
                .fireRespectingReduceMotion { content, reduceMotion in
                    content.transition(.fireListItem(reduceMotion: reduceMotion))
                }
            }

            if notificationStore.shouldShowFullPaginationRetry {
                Button {
                    retryFullLoad()
                } label: {
                    HStack {
                        Spacer()
                        Label("重试加载更多", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FireTheme.accent)
                            .padding(.vertical, 12)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if notificationStore.hasMoreFull {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 16)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .task {
                    await notificationStore.loadFullPage(
                        offset: notificationStore.fullNextOffset
                    )
                }
            }
        }
        .listStyle(.plain)
        .fireRespectingReduceMotion { content, reduceMotion in
            content.animation(
                FireMotionTokens.animation(for: .standard, reduceMotion: reduceMotion),
                value: notificationStore.fullNotifications.map(\.id)
            )
        }
    }

    private func emptyState(errorMessage: String?) -> some View {
        VStack(spacing: 16) {
            if let errorMessage {
                FireErrorBanner(
                    message: errorMessage,
                    copied: false,
                    onCopy: {
                        UIPasteboard.general.string = errorMessage
                    },
                    onDismiss: {
                        notificationStore.clearFullError()
                    }
                )
            }

            Image(systemName: "bell.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(FireTheme.tertiaryInk)

            Text("暂无通知")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("刷新") {
                retryFullLoad()
            }
            .buttonStyle(FireSecondaryButtonStyle())
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleNotificationTap(_ item: NotificationItemState) {
        if !item.read {
            notificationStore.markRead(id: item.id)
        }

        selectedRoute = item.appRoute
    }
}
