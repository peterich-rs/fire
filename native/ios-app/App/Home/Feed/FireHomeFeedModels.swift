import UIKit

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

enum FireHomeCollectionSection: Int, Hashable {
    case scopeStatus
    case content
}

enum FireHomeCollectionItem: Hashable {
    case scopeStatus
    case blockingError(String)
    case inlineErrorBanner(String)
    case topic(UInt64)
    case loadingSkeleton(Int)
    case emptyState
    case appendingFooter
}
