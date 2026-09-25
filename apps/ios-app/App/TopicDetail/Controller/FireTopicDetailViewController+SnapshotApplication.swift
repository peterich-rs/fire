import UIKit

let fireTopicDetailSnapshotBuildDiagnosticThresholdMs: Int64 = 50
let fireTopicDetailSnapshotApplyDiagnosticThresholdMs: Int64 = 16

struct FireTopicDetailRevisionFingerprint: Equatable {
    let collection: UInt64
    let chrome: UInt64
    let sidecar: UInt64
    let interaction: UInt64
}

@MainActor
extension FireTopicDetailViewController {
    func buildRuntimeConfiguration(from state: FireTopicDetailPageState) -> FireTopicDetailRuntimeConfiguration {
        FireTopicDetailRuntimeConfiguration(
            viewModel: viewModel,
            displayedCategory: state.route.displayedCategory,
            currentUsername: state.route.currentUsername,
            row: state.route.row,
            baseURLString: state.route.baseURLString,
            snapshot: topicDetailStore.snapshot(for: state.topic.id),
            detail: state.feed.detail,
            renderState: state.feed.renderState,
            pendingScrollTarget: state.feed.pendingScrollTarget,
            detailError: state.feed.detailError,
            detailNotice: state.feed.detailNotice,
            hasMoreTopicPosts: state.feed.hasMoreTopicPosts,
            isLoadingTopic: state.feed.isLoadingTopic,
            isLoadingMoreTopicPosts: state.feed.isLoadingMoreTopicPosts,
            loadMoreTopicPostsError: state.feed.loadMoreTopicPostsError,
            topicAiSummary: state.sidecar.topicAiSummary,
            isLoadingTopicAiSummary: state.sidecar.isLoadingTopicAiSummary,
            topicAiSummaryError: state.sidecar.topicAiSummaryError,
            isTopicAiSummaryExpanded: isTopicAiSummaryExpanded,
            topicCollectionRevision: state.feed.topicCollectionRevision,
            canWriteInteractions: state.route.canWriteInteractions,
            postLookup: state.feed.postLookup,
            interactionState: state.interaction,
            activeSearchPostID: activeTopicSearchMatch?.postID,
            snapshotInvalidationToken: AnyHashable(FireTopicDetailFeedInvalidationToken(
                topicID: state.topic.id,
                topicCollectionRevision: state.feed.topicCollectionRevision,
                pendingScrollTarget: state.feed.pendingScrollTarget,
                detailError: state.feed.detailError ?? "",
                detailNotice: state.feed.detailNotice,
                hasDetail: state.feed.detail != nil,
                isLoadingTopic: state.feed.isLoadingTopic,
                isLoadingMoreTopicPosts: state.feed.isLoadingMoreTopicPosts,
                loadMoreTopicPostsError: state.feed.loadMoreTopicPostsError ?? "",
                hasMoreTopicPosts: state.feed.hasMoreTopicPosts,
                canWriteInteractions: state.route.canWriteInteractions,
                currentUsername: state.route.currentUsername ?? "",
                baseURLString: state.route.baseURLString,
                activeSearchPostID: activeTopicSearchMatch?.postID,
                expandedReplyRootPostIDs: state.interaction.expandedReplyRootPostIDs,
                expandedReactionPickerPostIDs: state.interaction.expandedReactionPickerPostIDs
            )),
            interactions: runtimeInteractions
        )
    }

    func buildAndApplySnapshot(reuseComments: Bool = false) {
        snapshotBuildGeneration &+= 1
        let generation = snapshotBuildGeneration
        let pageState = buildCurrentPageState()
        let configuration = buildRuntimeConfiguration(from: pageState)
        let input = FireTopicDetailSnapshotInput(
            configuration: configuration,
            toolbarState: snapshotAssembler.makeToolbarState(from: pageState.chrome),
            quickReplyState: snapshotAssembler.makeQuickReplyState(from: pageState.composer),
            pendingScrollTarget: pageState.feed.pendingScrollTarget,
            invalidationToken: configuration.snapshotInvalidationToken
        )

        applyChromeState(chrome: pageState.chrome, composer: pageState.composer)

        snapshotBuildTask?.cancel()
        let logger = viewModel.topicDetailLogger()
        let cachedComments = reuseComments ? lastFeedSnapshot : nil
        snapshotBuildTask = Task.detached(priority: .userInitiated) { [weak self, snapshotAssembler, input, configuration, generation, logger, cachedComments] in
            let buildStartedAt = Date()
            let snapshot = snapshotAssembler.buildSnapshot(from: input, reusingComments: cachedComments)
            let buildDurationMs = Self.elapsedMilliseconds(since: buildStartedAt)
            if buildDurationMs >= fireTopicDetailSnapshotBuildDiagnosticThresholdMs {
                logger?.debug(
                    "topic detail snapshot build slow topic_id=\(configuration.row.topic.id) generation=\(generation) build_ms=\(buildDurationMs) item_count=\(snapshot.items.count)"
                )
            }

            await MainActor.run { [weak self] in
                guard let self,
                      self.snapshotBuildGeneration == generation,
                      !Task.isCancelled else {
                    return
                }
                self.applyBuiltSnapshot(
                    snapshot,
                    configuration: configuration,
                    buildDurationMs: buildDurationMs
                )
            }
        }
    }

    /// Local expand / picker / reply-tree toggles stay on the main thread so a
    /// single row can relayout without a detached full-page snapshot rebuild.
    func applyLocalInteractionSnapshot() {
        snapshotBuildGeneration &+= 1
        snapshotBuildTask?.cancel()
        snapshotBuildTask = nil
        let pageState = buildCurrentPageState()
        let configuration = buildRuntimeConfiguration(from: pageState)
        let input = FireTopicDetailSnapshotInput(
            configuration: configuration,
            toolbarState: snapshotAssembler.makeToolbarState(from: pageState.chrome),
            quickReplyState: snapshotAssembler.makeQuickReplyState(from: pageState.composer),
            pendingScrollTarget: pageState.feed.pendingScrollTarget,
            invalidationToken: configuration.snapshotInvalidationToken
        )
        applyChromeState(chrome: pageState.chrome, composer: pageState.composer)
        let snapshot = snapshotAssembler.buildSnapshot(from: input)
        applyBuiltSnapshot(
            snapshot,
            configuration: configuration,
            buildDurationMs: 0
        )
    }

    func buildAndApplyChromeState() {
        let topicId = row.topic.id
        applyChromeState(
            chrome: buildCurrentChromeState(topicId: topicId),
            composer: buildCurrentComposerState(topicId: topicId)
        )
    }

    func applyChromeState(
        chrome: FireTopicDetailChromeState,
        composer: FireTopicDetailComposerState
    ) {
        toolbarCoordinator.apply(state: snapshotAssembler.makeToolbarState(from: chrome))
        quickReplyBar.apply(state: snapshotAssembler.makeQuickReplyState(from: composer))
        updateBottomChromeInset()
    }

    func applyBuiltSnapshot(
        _ snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration,
        buildDurationMs: Int64
    ) {
        let applyStartedAt = Date()
        lastFeedSnapshot = FireTopicDetailRuntimeSnapshot(
            items: snapshot.items,
            replyIndexByPostID: snapshot.replyIndexByPostID
        )
        feedUpdatePipeline.apply(snapshot: snapshot, configuration: configuration)
        // Collection updates can recreate Texture shells; keep canvas in sync with
        // the current appearance so dark→light survives data reload paths.
        applyAppearanceShell()
        let applyDurationMs = Self.elapsedMilliseconds(since: applyStartedAt)
        logSnapshotApply(
            snapshot: snapshot,
            configuration: configuration,
            buildDurationMs: buildDurationMs,
            applyDurationMs: applyDurationMs
        )
    }

    func logSnapshotApply(
        snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration,
        buildDurationMs: Int64,
        applyDurationMs: Int64
    ) {
        guard buildDurationMs >= fireTopicDetailSnapshotBuildDiagnosticThresholdMs
                || applyDurationMs >= fireTopicDetailSnapshotApplyDiagnosticThresholdMs
                || !feedController.isViewAttached else {
            return
        }
        viewModel.topicDetailLogger()?.debug(
            "topic detail snapshot apply diagnostic topic_id=\(topic.id) snapshot_build_ms=\(buildDurationMs) feed_apply_ms=\(applyDurationMs) snapshot_item_count=\(snapshot.items.count) topic_collection_revision=\(configuration.topicCollectionRevision) has_detail=\(configuration.detail != nil) feed_attached=\(feedController.isViewAttached)"
        )
    }

    func layoutDiagnosticsSignature() -> String {
        "bounds=\(Self.formatSize(view.bounds.size)) safe_bottom=\(Int(view.safeAreaInsets.bottom.rounded())) feed_attached=\(feedController.isViewAttached)"
    }

    func shouldLogLayoutDiagnostics(signature: String) -> Bool {
        guard lastLayoutDiagnosticsSignature == signature else {
            lastLayoutDiagnosticsSignature = signature
            repeatedLayoutDiagnosticsCount = 0
            return true
        }
        repeatedLayoutDiagnosticsCount += 1
        return repeatedLayoutDiagnosticsCount.isMultiple(of: 500)
    }

    func handleLayoutRevisionChanged() {
        guard let snapshot = feedUpdatePipeline.currentSnapshot,
              let configuration = feedUpdatePipeline.currentConfiguration else {
            return
        }
        feedController.applyPublishedLayoutRevision(
            publishedKeys: layoutManager.currentPublishedKeys,
            items: snapshot.items,
            configuration: configuration
        )
    }
}
