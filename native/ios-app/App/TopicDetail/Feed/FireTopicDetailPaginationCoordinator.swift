import Foundation

@MainActor
final class FireTopicDetailPaginationCoordinator {
    weak var feedController: FireTopicDetailFeedController?

    var configuration: FireTopicDetailRuntimeConfiguration?

    private var lastLoadMoreProbe: FireTopicDetailLoadMoreProbe?
    private var lastRejectedLoadMoreProbe: FireTopicDetailLoadMoreProbe?

    func resetRejectedProbeIfNeeded(
        previousInvalidationToken: AnyHashable?,
        nextInvalidationToken: AnyHashable
    ) {
        if previousInvalidationToken != nextInvalidationToken {
            lastRejectedLoadMoreProbe = nil
        }
    }

    @discardableResult
    func loadMoreIfNeeded(
        itemCount: Int,
        visibleMaxItem: Int?,
        forceEvaluation: Bool = false
    ) -> Bool {
        guard let configuration,
              configuration.detail != nil,
              configuration.hasMoreTopicPosts,
              configuration.loadMoreTopicPostsError == nil,
              !configuration.isLoadingMoreTopicPosts else {
            return false
        }

        let probe = fireTopicDetailLoadMoreProbe(
            itemCount: itemCount,
            visibleMaxItem: visibleMaxItem
        )

        guard forceEvaluation || lastLoadMoreProbe != probe else {
            return false
        }

        if fireTopicDetailShouldLoadMore(
            itemCount: probe.itemCount,
            visibleMaxItem: probe.visibleMaxItem
        ) {
            return attemptLoadMore(
                probe: probe,
                allowRetry: true,
                bypassRejectedProbeGuard: forceEvaluation
            )
        }

        lastLoadMoreProbe = probe
        lastRejectedLoadMoreProbe = nil
        return false
    }

    func requestLoadMore(forceEvaluation: Bool, allowRetry _: Bool) {
        if forceEvaluation,
           let configuration,
           configuration.detail != nil,
           configuration.hasMoreTopicPosts,
           !configuration.isLoadingMoreTopicPosts,
           let probe = currentLoadMoreProbe() {
            _ = attemptLoadMore(
                probe: probe,
                allowRetry: false,
                bypassRejectedProbeGuard: true
            )
            return
        }

        guard let feedController else { return }
        _ = loadMoreIfNeeded(
            itemCount: feedController.currentItems.count,
            visibleMaxItem: feedController.visibleMaxItem,
            forceEvaluation: false
        )
    }

    func recordCollectionUpdateCompleted() {
        guard let feedController else { return }
        lastLoadMoreProbe = fireTopicDetailLoadMoreProbe(
            itemCount: feedController.currentItems.count,
            visibleMaxItem: feedController.visibleMaxItem
        )
        lastRejectedLoadMoreProbe = nil
    }

    private func currentLoadMoreProbe() -> FireTopicDetailLoadMoreProbe? {
        guard let feedController, let configuration, configuration.detail != nil else {
            return nil
        }
        return fireTopicDetailLoadMoreProbe(
            itemCount: feedController.currentItems.count,
            visibleMaxItem: feedController.visibleMaxItem
        )
    }

    @discardableResult
    private func attemptLoadMore(
        probe: FireTopicDetailLoadMoreProbe,
        allowRetry _: Bool,
        bypassRejectedProbeGuard: Bool
    ) -> Bool {
        guard let configuration else { return false }
        if !bypassRejectedProbeGuard, lastRejectedLoadMoreProbe == probe {
            return false
        }
        if configuration.onLoadMoreTopicPosts() {
            lastLoadMoreProbe = probe
            lastRejectedLoadMoreProbe = nil
            return true
        }

        lastLoadMoreProbe = probe
        lastRejectedLoadMoreProbe = probe
        return false
    }
}
