import Foundation

private let fireTopicDetailVisibilityPublishDebounce = Duration.milliseconds(240)

@MainActor
final class FireTopicDetailVisibilityCoordinator {
    weak var feedController: FireTopicDetailFeedController?

    var onVisiblePostNumbersChanged: ((Set<UInt32>) -> Void)?
    var onScrollTargetHandled: ((UInt32) -> Void)?

    private var handledScrollTarget: UInt32?
    private var lastPublishedVisiblePostNumbers: Set<UInt32> = []
    private var visiblePostNumbersPublishTask: Task<Void, Never>?
    private var pendingVisiblePostNumbers: Set<UInt32>?

    deinit {
        visiblePostNumbersPublishTask?.cancel()
    }

    func publishIfChanged(items: [FireTopicDetailRuntimeItem], force: Bool = false) {
        guard let feedController else { return }
        let postNumbers = feedController.currentVisiblePostNumbers(items: items)

        if force {
            visiblePostNumbersPublishTask?.cancel()
            visiblePostNumbersPublishTask = nil
            pendingVisiblePostNumbers = nil
            publishVisiblePostNumbersImmediately(postNumbers, force: true)
            return
        }

        guard postNumbers != lastPublishedVisiblePostNumbers else {
            pendingVisiblePostNumbers = nil
            visiblePostNumbersPublishTask?.cancel()
            visiblePostNumbersPublishTask = nil
            return
        }

        pendingVisiblePostNumbers = postNumbers
        guard visiblePostNumbersPublishTask == nil else {
            return
        }

        visiblePostNumbersPublishTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: fireTopicDetailVisibilityPublishDebounce)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            let latestPostNumbers = self.pendingVisiblePostNumbers ?? postNumbers
            self.pendingVisiblePostNumbers = nil
            self.visiblePostNumbersPublishTask = nil
            self.publishVisiblePostNumbersImmediately(latestPostNumbers)
        }
    }

    func handlePendingScrollTargetIfNeeded(
        _ target: UInt32?,
        items: [FireTopicDetailRuntimeItem]
    ) {
        guard let feedController else { return }
        var handledTarget = handledScrollTarget
        feedController.handlePendingScrollTarget(
            target,
            handledTarget: &handledTarget
        ) { [weak self] postNumber in
            self?.onScrollTargetHandled?(postNumber)
        }
        handledScrollTarget = handledTarget
    }

    private func publishVisiblePostNumbersImmediately(
        _ postNumbers: Set<UInt32>,
        force: Bool = false
    ) {
        guard force || postNumbers != lastPublishedVisiblePostNumbers else {
            return
        }
        lastPublishedVisiblePostNumbers = postNumbers
        onVisiblePostNumbersChanged?(postNumbers)
    }
}
