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
    @Namespace private var pushTransitionNamespace

    private static let paginationPrefetchDistance: CGFloat = 480

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
                onRefresh: refreshTopics,
                onScrollMetricsChanged: handleTopicListScrollMetricsChange(_: )
            )
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

                        NavigationLink {
                            FireSearchView(appViewModel: viewModel, searchStore: searchStore)
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
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
        .alert("提示", isPresented: Binding(
            get: { composerNotice != nil },
            set: { presenting in
                if !presenting {
                    composerNotice = nil
                }
            }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(composerNotice ?? "")
        }
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
        selectedRoute = route
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
        selectedRoute = route
        navigationState.pendingRoute = nil
    }
}
