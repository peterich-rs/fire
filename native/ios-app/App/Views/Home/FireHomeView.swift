import SwiftUI

func fireHomeShouldRequestNextPage(
    nextTopicsPage: UInt32?,
    lastTriggeredTopicsPage: UInt32?,
    isLoadingTopics: Bool,
    metrics: FireCollectionScrollMetrics,
    paginationPrefetchDistance: CGFloat,
    didPrefetchToFillViewport: Bool
) -> Bool {
    guard let nextTopicsPage else {
        return false
    }
    guard !isLoadingTopics else {
        return false
    }

    let contentFitsViewport = metrics.contentHeight <= metrics.visibleHeight + 1
    if contentFitsViewport {
        guard !didPrefetchToFillViewport else {
            return false
        }
    } else {
        let isNearBottom = metrics.remainingDistanceToBottom <= paginationPrefetchDistance
        guard isNearBottom else {
            return false
        }
    }

    return lastTriggeredTopicsPage != nextTopicsPage
}

struct FireHomeView: View {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter
    @EnvironmentObject private var navigationState: FireNavigationState
    @EnvironmentObject private var homeFeedStore: FireHomeFeedStore
    let viewModel: FireAppViewModel
    let searchStore: FireSearchStore
    @State private var showCategoryBrowser = false
    @State private var showTagPicker = false
    @State private var showCreateTopicComposer = false
    @State private var didPrefetchToFillViewport = false
    @State private var selectedRoute: FireAppRoute?
    @State private var lastTriggeredTopicsPage: UInt32?
    @State private var composerNotice: String?
    @State private var toast: FireToast?
    @State private var editingBookmarkContext: FireBookmarkEditorContext?
    @Namespace private var pushTransitionNamespace

    private static let paginationPrefetchDistance: CGFloat = 480

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var body: some View {
        NavigationStack {
            FireHomeCollectionView(
                onShowCategoryBrowser: {
                    showCategoryBrowser = true
                },
                onShowTagPicker: {
                    showTagPicker = true
                },
                onSelectTopic: selectTopic(_:),
                onEditTopicBookmark: { row in
                    editingBookmarkContext = row.fireBookmarkEditorContext()
                },
                onMuteTopic: muteTopic(_:),
                onRefresh: refreshTopics,
                onScrollMetricsChanged: handleTopicListScrollMetricsChange(_: ),
                baseURLString: baseURLString
            )
            .overlay(alignment: .top) {
                if homeFeedStore.isOffline {
                    FireOfflineBanner()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: homeFeedStore.isOffline)
            .onAppear {
                homeFeedStore.setTopicListVisible(true)
            }
            .onDisappear {
                homeFeedStore.setTopicListVisible(false)
            }
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            showCreateTopicComposer = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("创建新话题")

                        NavigationLink {
                            FireSearchView(appViewModel: viewModel, searchStore: searchStore)
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("搜索")
                    }
                }
            }
            .navigationDestination(isPresented: isRoutePresented) {
                if let route = selectedRoute {
                    FireAppRouteDestinationView(viewModel: viewModel, route: route)
                        .id(route.id)
                        .fireNavigationPush(
                            sourceID: "home-route",
                            namespace: pushTransitionNamespace
                        )
                }
            }
        }
        .onAppear {
            consumePendingRouteIfVisible(navigationState.pendingRoute)
        }
        .task {
            await homeFeedStore.refreshTopicsIfPossible(force: false)
        }
        .onChange(of: navigationState.pendingRoute) { _, route in
            consumePendingRouteIfVisible(route)
        }
        .onChange(of: homeFeedStore.selectedTopicKind) { _, _ in
            resetPaginationTracking()
        }
        .onChange(of: homeFeedStore.selectedHomeCategoryId) { _, _ in
            resetPaginationTracking()
        }
        .onChange(of: homeFeedStore.selectedHomeTags) { _, _ in
            resetPaginationTracking()
        }
        .onChange(of: homeFeedStore.currentScopeNextTopicsPage) { _, nextPage in
            guard let nextPage else {
                lastTriggeredTopicsPage = nil
                return
            }
            if let lastTriggeredTopicsPage,
               nextPage <= lastTriggeredTopicsPage {
                self.lastTriggeredTopicsPage = nil
            }
        }
        .onChange(of: homeFeedStore.topicLoadErrorMessage) { _, message in
            if message != nil {
                lastTriggeredTopicsPage = nil
            }
        }
        .onChange(of: composerNotice) { _, message in
            showToast(message, style: .info)
        }
        .sheet(isPresented: $showCategoryBrowser) {
            FireCategoryBrowserSheet(viewModel: viewModel)
                .fireSheet(presented: $showCategoryBrowser)
        }
        .sheet(isPresented: $showTagPicker) {
            FireTagPickerSheet(viewModel: viewModel)
                .fireSheet(presented: $showTagPicker)
        }
        .fullScreenCover(isPresented: $showCreateTopicComposer) {
            NavigationStack {
                FireComposerView(
                    viewModel: viewModel,
                    route: FireComposerRoute(kind: .createTopic),
                    initialCategoryID: homeFeedStore.selectedHomeCategoryId,
                    initialTags: homeFeedStore.selectedHomeTags,
                    onTopicCreated: { _ in
                        showCreateTopicComposer = false
                    },
                    onSubmissionNotice: { message in
                        composerNotice = message
                    }
                )
            }
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
                    await homeFeedStore.refreshTopicsAsync()
                },
                onDelete: context.bookmarkID.map { bookmarkID in
                    {
                        try await viewModel.topicInteraction.deleteBookmark(bookmarkID: bookmarkID)
                        await homeFeedStore.refreshTopicsAsync()
                    }
                }
            )
        }
        .fireToast($toast)
    }

    private func resetPaginationTracking() {
        didPrefetchToFillViewport = false
        lastTriggeredTopicsPage = nil
    }

    private var isRoutePresented: Binding<Bool> {
        Binding(
            get: { selectedRoute != nil },
            set: { isPresented in
                if !isPresented {
                    selectedRoute = nil
                }
            }
        )
    }

    private func refreshTopics() async {
        await homeFeedStore.refreshTopicsAsync()
    }

    private func selectTopic(_ route: FireAppRoute) {
        presentRoute(route)
    }

    private func muteTopic(_ row: FireTopicRowPresentation) {
        Task {
            do {
                try await viewModel.topicInteraction.setTopicNotificationLevel(
                    topicID: row.topic.id,
                    notificationLevel: FireTopicNotificationLevelOption.muted.rawValue
                )
                showToast("已静音话题", style: .success)
            } catch {
                showToast(error.localizedDescription, style: .error)
            }
        }
    }

    private func showToast(_ message: String?, style: FireToastStyle) {
        guard let message,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        toast = FireToast(message: message, style: style)
        composerNotice = nil
    }

    private func handleTopicListScrollMetricsChange(_ newMetrics: FireCollectionScrollMetrics) {
        guard fireHomeShouldRequestNextPage(
            nextTopicsPage: homeFeedStore.currentScopeNextTopicsPage,
            lastTriggeredTopicsPage: lastTriggeredTopicsPage,
            isLoadingTopics: homeFeedStore.isLoadingTopics,
            metrics: newMetrics,
            paginationPrefetchDistance: Self.paginationPrefetchDistance,
            didPrefetchToFillViewport: didPrefetchToFillViewport
        ) else {
            return
        }
        guard let nextTopicsPage = homeFeedStore.currentScopeNextTopicsPage else { return }

        if newMetrics.contentHeight <= newMetrics.visibleHeight + 1 {
            didPrefetchToFillViewport = true
        }
        lastTriggeredTopicsPage = nextTopicsPage
        homeFeedStore.loadMoreTopics()
    }

    private func consumePendingRouteIfVisible(_ route: FireAppRoute?) {
        guard navigationState.selectedTab == 0, let route else {
            return
        }
        presentRoute(route)
        navigationState.pendingRoute = nil
    }

    private func presentRoute(_ route: FireAppRoute) {
        if topicRoutePresenter.present(route) {
            return
        }
        selectedRoute = route
    }
}
