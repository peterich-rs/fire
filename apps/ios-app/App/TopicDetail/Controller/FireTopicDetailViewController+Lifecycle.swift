import Combine
import UIKit

@MainActor
extension FireTopicDetailViewController {
    func beginPageLifecycle() {
        viewModel.topicDetailLogger()?.info(
            "topic detail lifecycle begin topic_id=\(row.topic.id) owner_token=\(detailOwnerToken)"
        )
        let hasReadySnapshot = topicDetailStore.snapshot(for: row.topic.id)?.phase == .ready
        topicDetailStore.open(
            topicId: row.topic.id,
            ownerToken: detailOwnerToken,
            slug: displayedTopicSlug.isEmpty ? nil : displayedTopicSlug,
            targetPostNumber: scrollToPostNumber,
            bypassCache: false,
            forceLoad: false,
            trackVisit: true,
            allowSuggestedUnreadRoot: scrollToPostNumber == nil && !hasReadySnapshot
        )

        timingTracker.start { [weak viewModel] topicId, topicTimeMs, timings in
            guard let viewModel else { return false }
            return await viewModel.topicInteraction.reportTopicTimings(
                topicId: topicId,
                topicTimeMs: topicTimeMs,
                timings: timings
            )
        }

        subscribeToKeyboardNotifications()
        subscribeToStoreRevisions()
        kickOffInitialLoad()
        // The Rust topic session subscribes to detail, reactions, polls, and presence.
        viewModel.topicDetailLogger()?.debug(
            "topic detail lifecycle begin scheduled tasks topic_id=\(row.topic.id) owner_token=\(detailOwnerToken)"
        )
    }

    func endPageLifecycle() {
        viewModel.topicDetailLogger()?.info(
            "topic detail lifecycle end topic_id=\(row.topic.id) owner_token=\(detailOwnerToken)"
        )
        initialLoadTask?.cancel()
        initialLoadTask = nil
        subscriptionTask?.cancel()
        subscriptionTask = nil
        snapshotBuildTask?.cancel()
        snapshotBuildTask = nil
        pendingSnapshotWork = nil
        cancellables.removeAll()
        topicDetailStore.noteScrollInteraction(topicId: row.topic.id, active: false)

        topicDetailStore.close(topicId: row.topic.id, ownerToken: detailOwnerToken)
    }

    func kickOffInitialLoad() {
        initialLoadTask?.cancel()
        viewModel.topicDetailLogger()?.info(
            "topic detail initial load task scheduled topic_id=\(row.topic.id) target_post=\(scrollToPostNumber.map(String.init) ?? "nil")"
        )
        initialLoadTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            self.viewModel.topicDetailLogger()?.info(
                "topic detail initial load task start topic_id=\(self.row.topic.id) target_post=\(self.scrollToPostNumber.map(String.init) ?? "nil")"
            )
            _ = self.topicDetailStore.snapshot(for: self.row.topic.id)
            self.viewModel.topicDetailLogger()?.info(
                "topic detail initial load task complete topic_id=\(self.row.topic.id) elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt)) cancelled=\(Task.isCancelled)"
            )
        }
    }

    func kickOffMessageBusSubscription() {
        subscriptionTask?.cancel()
        viewModel.topicDetailLogger()?.debug(
            "topic detail messagebus subscription task scheduled topic_id=\(row.topic.id) owner_token=\(detailOwnerToken)"
        )
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            self.viewModel.topicDetailLogger()?.debug(
                "topic detail messagebus subscription task start topic_id=\(self.row.topic.id) owner_token=\(self.detailOwnerToken)"
            )
            await self.viewModel.maintainTopicDetailSubscription(
                topicId: self.row.topic.id,
                ownerToken: self.detailOwnerToken
            )
            self.viewModel.topicDetailLogger()?.debug(
                "topic detail messagebus subscription task complete topic_id=\(self.row.topic.id) cancelled=\(Task.isCancelled)"
            )
        }
    }

    func loadTopicDetail(
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        let topicSlug = displayedTopicSlug
        let startedAt = Date()
        viewModel.topicDetailLogger()?.info(
            "topic detail controller load request start topic_id=\(row.topic.id) force=\(force) target_post=\(targetPostNumber.map(String.init) ?? "nil") slug_present=\(!topicSlug.isEmpty)"
        )
        let hasReadySnapshot = topicDetailStore.snapshot(for: row.topic.id)?.phase == .ready
        topicDetailStore.open(
            topicId: row.topic.id,
            ownerToken: detailOwnerToken,
            slug: topicSlug.isEmpty ? nil : topicSlug,
            targetPostNumber: targetPostNumber,
            bypassCache: force,
            forceLoad: force,
            trackVisit: true,
            allowSuggestedUnreadRoot: targetPostNumber == nil && !hasReadySnapshot
        )
        let loaded = topicDetailStore.snapshot(for: row.topic.id)
        viewModel.topicDetailLogger()?.info(
            "topic detail controller load request complete topic_id=\(row.topic.id) elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt)) phase=\(String(describing: loaded?.phase)) rows=\(loaded?.rows.count ?? 0)"
        )
    }

    func subscribeToStoreRevisions() {
        let topicId = row.topic.id
        topicDetailStore.$snapshots
            .map { snapshots -> FireTopicDetailRevisionFingerprint in
                let snapshot = snapshots[topicId]
                return FireTopicDetailRevisionFingerprint(
                    collection: snapshot?.collectionRevision ?? 0,
                    chrome: snapshot?.chromeRevision ?? 0,
                    sidecar: snapshot?.sidecarRevision ?? 0,
                    interaction: snapshot?.interactionRevision ?? 0,
                    composer: snapshot?.composerRevision ?? 0
                )
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] revisions in
                guard let self else { return }
                let collectionChanged = revisions.collection != self.lastAppliedCollectionRevision
                let chromeChanged = revisions.chrome != self.lastAppliedChromeRevision
                let sidecarChanged = revisions.sidecar != self.lastAppliedSidecarRevision
                let interactionChanged = revisions.interaction != self.lastAppliedInteractionRevision
                let composerChanged = revisions.composer != self.lastAppliedComposerRevision
                self.lastAppliedCollectionRevision = revisions.collection
                self.lastAppliedChromeRevision = revisions.chrome
                self.lastAppliedSidecarRevision = revisions.sidecar
                self.lastAppliedInteractionRevision = revisions.interaction
                self.lastAppliedComposerRevision = revisions.composer

                // Typing users and the submit state live in the quick reply
                // bar only; they never rebuild feed rows.
                if chromeChanged || composerChanged {
                    self.buildAndApplyChromeState()
                }
                guard collectionChanged || chromeChanged || sidecarChanged || interactionChanged else {
                    return
                }
                if interactionChanged, !collectionChanged, !sidecarChanged {
                    self.applyInteractionRowUpdates()
                    return
                }
                let reuseComments = !collectionChanged && !interactionChanged
                self.buildAndApplySnapshot(reuseComments: reuseComments)
            }
            .store(in: &cancellables)
    }

    func performRefresh() async {
        timingTracker.recordInteraction()
        topicDetailStore.clearScrollTarget(topicId: topic.id)
        await loadTopicDetail(force: true)
        // Force-load rebuilds Texture nodes; re-assert shell so dark→light survives PTR.
        applyAppearanceShell()
    }

    func handleVisiblePostNumbersChanged(_ visiblePostNumbers: Set<UInt32>) {
        if !visiblePostNumbers.isEmpty {
            timingTracker.recordInteraction()
        }
        timingTracker.updateVisiblePostNumbers(visiblePostNumbers)

        topicDetailStore.noteVisiblePosts(
            topicId: topic.id,
            postNumbers: visiblePostNumbers
        )
        maybePresentReactionPickerCoachmark(visiblePostNumbers: visiblePostNumbers)
    }
}
