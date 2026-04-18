import SwiftUI

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
    @State private var lastTopicListScrollMetrics: FireCollectionScrollMetrics?

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
            .navigationDestination(item: $selectedRoute) { route in
                FireAppRouteDestinationView(viewModel: viewModel, route: route)
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
                    initialCategoryID: homeFeedStore.selectedHomeCategoryId,
                    initialTags: homeFeedStore.selectedHomeTags,
                    onTopicCreated: { _ in
                        showCreateTopicComposer = false
                    }
                )
            }
        }
    }

    private func resetPaginationTracking() {
        didPrefetchToFillViewport = false
        lastTopicListScrollMetrics = nil
    }

    private func refreshTopics() async {
        await homeFeedStore.refreshTopicsAsync()
    }

    private func selectTopic(_ route: FireAppRoute) {
        selectedRoute = route
    }

    private func handleTopicListScrollMetricsChange(_ newMetrics: FireCollectionScrollMetrics) {
        defer {
            lastTopicListScrollMetrics = newMetrics
        }

        guard homeFeedStore.currentScopeNextTopicsPage != nil else { return }
        guard !homeFeedStore.isLoadingTopics else { return }

        let contentFitsViewport = newMetrics.contentHeight <= newMetrics.visibleHeight + 1
        if contentFitsViewport && !didPrefetchToFillViewport {
            didPrefetchToFillViewport = true
            homeFeedStore.loadMoreTopics()
            return
        }

        guard let oldMetrics = lastTopicListScrollMetrics else { return }
        guard oldMetrics.remainingDistanceToBottom > Self.paginationPrefetchDistance else { return }
        guard newMetrics.remainingDistanceToBottom <= Self.paginationPrefetchDistance else { return }
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
