import UIKit

extension FireHomeViewController {
    func handleVisibleItemsChanged(_ items: [FireHomeCollectionItem]) {
        let visibleTopicIDs: Set<UInt64> = Set(items.compactMap { item in
            guard case let .topic(topicID) = item else { return nil }
            return topicID
        })
        homeFeedStore.updateVisibleTopicIDs(visibleTopicIDs)
    }

    func handlePrefetchItems(_ items: [FireHomeCollectionItem]) {
        guard homeFeedStore.currentScopeNextTopicsPage != nil else { return }
        guard !homeFeedStore.isLoadingTopics else { return }

        if items.contains(.appendingFooter) {
            homeFeedStore.loadMoreTopics()
            return
        }

        let prefetchedTopicIDs = Set(items.compactMap { item -> UInt64? in
            guard case let .topic(topicID) = item else { return nil }
            return topicID
        })
        guard !prefetchedTopicIDs.isEmpty else { return }

        let rows = homeFeedStore.topicRows
        let prefetchThreshold = 5
        if let furthestIndex = rows.lastIndex(where: { prefetchedTopicIDs.contains($0.topic.id) }),
           rows.count - furthestIndex <= prefetchThreshold {
            homeFeedStore.loadMoreTopics()
        }
    }

    func handleTopicListScrollMetricsChange(_ newMetrics: FireCollectionScrollMetrics) {
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

    func resetPaginationTracking() {
        didPrefetchToFillViewport = false
        lastTriggeredTopicsPage = nil
    }

    func syncNextPageTracking() {
        guard let nextPage = homeFeedStore.currentScopeNextTopicsPage else {
            lastTriggeredTopicsPage = nil
            return
        }
        if let lastTriggeredTopicsPage,
           nextPage <= lastTriggeredTopicsPage {
            self.lastTriggeredTopicsPage = nil
        }
    }
}
