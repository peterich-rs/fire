import UIKit

let fireTopicDetailSnapshotBuildDiagnosticThresholdMs: Int64 = 50
let fireTopicDetailSnapshotApplyDiagnosticThresholdMs: Int64 = 16

struct FireTopicDetailDeferredFeedApply {
    let snapshot: FireTopicDetailPageSnapshot
    let configuration: FireTopicDetailRuntimeConfiguration
    let buildDurationMs: Int64
}

struct FireTopicDetailRevisionFingerprint: Equatable {
    let collection: UInt64
    let chrome: UInt64
    let sidecar: UInt64
    let interaction: UInt64
    let composer: UInt64
}

/// Feed work that still has to adopt the latest Rust snapshot off the main
/// thread. At most one is pending; a newer request merges into it instead of
/// cancelling it, so a structural rebuild is never replaced by a row patch.
enum FireTopicDetailSnapshotWork: Equatable, Sendable {
    /// `rebuildsComments == false` reuses the last built comment rows.
    case fullBuild(rebuildsComments: Bool)
    /// Row content changed in place; patch post items on the last built rows.
    case interactionRows

    func merged(with next: Self) -> Self {
        switch (self, next) {
        case (.interactionRows, .interactionRows):
            return .interactionRows
        case let (.fullBuild(current), .fullBuild(incoming)):
            return .fullBuild(rebuildsComments: current || incoming)
        case (.fullBuild, .interactionRows), (.interactionRows, .fullBuild):
            return .fullBuild(rebuildsComments: true)
        }
    }
}

@MainActor
extension FireTopicDetailViewController {
    /// The newest built feed rows, including a batch still waiting for the
    /// scroll to settle. Row patches must build on this, not on the last
    /// committed rows, or they would drop the waiting batch.
    var latestBuiltFeedSnapshot: FireTopicDetailRuntimeSnapshot? {
        if let deferredFeedApply {
            return FireTopicDetailRuntimeSnapshot(
                items: deferredFeedApply.snapshot.items,
                replyIndexByPostID: deferredFeedApply.snapshot.replyIndexByPostID
            )
        }
        return lastFeedSnapshot
    }

    func buildRuntimeConfiguration(from state: FireTopicDetailPageState) -> FireTopicDetailRuntimeConfiguration {
        let rustSnapshot = topicDetailStore.snapshot(for: state.topic.id)
        return FireTopicDetailRuntimeConfiguration(
            viewModel: viewModel,
            displayedCategory: state.route.displayedCategory,
            currentUsername: state.route.currentUsername,
            row: state.route.row,
            baseURLString: state.route.baseURLString,
            snapshot: rustSnapshot,
            rowsByPostID: adoptedRenderProjection?.rowsByPostID ?? [:],
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
                hasDetail: rustSnapshot?.phase == .ready
                    || state.feed.detail != nil,
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
        applyChromeState(
            chrome: buildCurrentChromeState(topicId: row.topic.id),
            composer: buildCurrentComposerState(topicId: row.topic.id)
        )
        scheduleSnapshotWork(.fullBuild(rebuildsComments: !reuseComments))
    }

    /// Rows changed in place (reactions, polls, boosts, edits). Adoption runs
    /// off the main thread; only post items whose tokens moved are replaced.
    func applyInteractionRowUpdates() {
        guard latestBuiltFeedSnapshot != nil else {
            buildAndApplySnapshot()
            return
        }
        scheduleSnapshotWork(.interactionRows)
    }

    /// Local expand / picker / reply-tree toggles stay on the main thread so a
    /// single row can relayout without a detached full-page snapshot rebuild.
    /// They read the already adopted rows; pending adoption is restarted so it
    /// picks up the new local state instead of overwriting it.
    func applyLocalInteractionSnapshot(postIDs: Set<UInt64> = []) {
        let pageState = buildCurrentPageState()
        let configuration = buildRuntimeConfiguration(from: pageState)
        applyChromeState(chrome: pageState.chrome, composer: pageState.composer)
        if !postIDs.isEmpty, let base = latestBuiltFeedSnapshot {
            applyPostItemRefresh(
                base: base,
                pageState: pageState,
                configuration: configuration,
                where: postIDs.contains
            )
        } else {
            let snapshot = snapshotAssembler.buildSnapshot(from: FireTopicDetailSnapshotInput(
                configuration: configuration,
                toolbarState: snapshotAssembler.makeToolbarState(from: pageState.chrome),
                quickReplyState: snapshotAssembler.makeQuickReplyState(from: pageState.composer),
                pendingScrollTarget: pageState.feed.pendingScrollTarget,
                invalidationToken: configuration.snapshotInvalidationToken
            ))
            applyBuiltSnapshot(snapshot, configuration: configuration, buildDurationMs: 0)
        }
        if let pendingSnapshotWork {
            scheduleSnapshotWork(pendingSnapshotWork)
        }
    }

    private func scheduleSnapshotWork(_ work: FireTopicDetailSnapshotWork) {
        let merged = pendingSnapshotWork.map { $0.merged(with: work) } ?? work
        pendingSnapshotWork = merged
        snapshotBuildGeneration &+= 1
        let generation = snapshotBuildGeneration
        let rustSnapshot = topicDetailStore.snapshot(for: row.topic.id)
        let previousProjection = adoptedRenderProjection
        snapshotBuildTask?.cancel()
        snapshotBuildTask = Task.detached(priority: .userInitiated) { [weak self] in
            let adopted = rustSnapshot.map {
                FireTopicPresentation.adopt(snapshot: $0, reusing: previousProjection)
            }
            guard !Task.isCancelled else { return }
            await self?.finishSnapshotAdoption(adopted, generation: generation)
        }
    }

    private func finishSnapshotAdoption(
        _ adopted: FireTopicDetailAdoptedProjection?,
        generation: UInt64
    ) {
        guard snapshotBuildGeneration == generation,
              let work = pendingSnapshotWork else {
            return
        }
        adoptedRenderProjection = adopted
        switch work {
        case .interactionRows:
            pendingSnapshotWork = nil
            guard let base = latestBuiltFeedSnapshot else {
                buildAndApplySnapshot()
                return
            }
            let changed = adopted?.changedPostIDs ?? []
            guard !changed.isEmpty else { return }
            let pageState = buildCurrentPageState()
            applyPostItemRefresh(
                base: base,
                pageState: pageState,
                configuration: buildRuntimeConfiguration(from: pageState),
                where: { changed.contains($0) }
            )
        case .fullBuild(let rebuildsComments):
            startFullSnapshotBuild(rebuildsComments: rebuildsComments, generation: generation)
        }
    }

    private func startFullSnapshotBuild(rebuildsComments: Bool, generation: UInt64) {
        let pageState = buildCurrentPageState()
        let configuration = buildRuntimeConfiguration(from: pageState)
        let input = FireTopicDetailSnapshotInput(
            configuration: configuration,
            toolbarState: snapshotAssembler.makeToolbarState(from: pageState.chrome),
            quickReplyState: snapshotAssembler.makeQuickReplyState(from: pageState.composer),
            pendingScrollTarget: pageState.feed.pendingScrollTarget,
            invalidationToken: configuration.snapshotInvalidationToken
        )
        let cachedComments = (!rebuildsComments || configuration.isWaitingForPostRender)
            ? latestBuiltFeedSnapshot
            : nil
        let assembler = snapshotAssembler
        let logger = viewModel.topicDetailLogger()
        snapshotBuildTask = Task.detached(priority: .userInitiated) { [weak self] in
            let buildStartedAt = Date()
            let snapshot = assembler.buildSnapshot(from: input, reusingComments: cachedComments)
            let buildDurationMs = Self.elapsedMilliseconds(since: buildStartedAt)
            if buildDurationMs >= fireTopicDetailSnapshotBuildDiagnosticThresholdMs {
                logger?.debug(
                    "topic detail snapshot build slow topic_id=\(configuration.row.topic.id) generation=\(generation) build_ms=\(buildDurationMs) item_count=\(snapshot.items.count)"
                )
            }
            guard !Task.isCancelled else { return }
            await self?.finishFullSnapshotBuild(
                snapshot,
                configuration: configuration,
                generation: generation,
                buildDurationMs: buildDurationMs
            )
        }
    }

    private func finishFullSnapshotBuild(
        _ snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration,
        generation: UInt64,
        buildDurationMs: Int64
    ) {
        guard snapshotBuildGeneration == generation else { return }
        pendingSnapshotWork = nil
        applyBuiltSnapshot(snapshot, configuration: configuration, buildDurationMs: buildDurationMs)
    }

    /// Rebuilds the selected post items on `base` and applies the result when
    /// any rendered or in-place token moved.
    private func applyPostItemRefresh(
        base: FireTopicDetailRuntimeSnapshot,
        pageState: FireTopicDetailPageState,
        configuration: FireTopicDetailRuntimeConfiguration,
        where shouldRefresh: (UInt64) -> Bool
    ) {
        var didChange = false
        let items = base.items.map { item -> FireTopicDetailRuntimeItem in
            guard let postID = item.postID, shouldRefresh(postID) else { return item }
            let refreshed = configuration.refreshedPostItem(item)
            if refreshed.hasSameRenderedContent(as: item),
               refreshed.inPlaceUpdateToken == item.inPlaceUpdateToken {
                return item
            }
            didChange = true
            return refreshed
        }
        guard didChange else { return }
        let snapshot = FireTopicDetailPageSnapshot(
            items: items,
            replyIndexByPostID: base.replyIndexByPostID,
            canWriteInteractions: configuration.canWriteInteractions,
            hasDetail: configuration.hasLoadedTopic,
            toolbarState: snapshotAssembler.makeToolbarState(from: pageState.chrome),
            quickReplyState: snapshotAssembler.makeQuickReplyState(from: pageState.composer),
            pendingScrollTarget: pageState.feed.pendingScrollTarget,
            invalidationToken: configuration.snapshotInvalidationToken
        )
        applyBuiltSnapshot(snapshot, configuration: configuration, buildDurationMs: 0)
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
        let previousItems = lastFeedSnapshot?.items ?? []
        let plan = fireTopicDetailCollectionUpdatePlan(from: previousItems, to: snapshot.items)
        if fireTopicDetailShouldDeferCollectionApply(
            isScrollInteractionActive: feedController.isScrollInteractionActive,
            hasBatchUpdates: plan.hasBatchUpdates
        ) {
            deferredFeedApply = FireTopicDetailDeferredFeedApply(
                snapshot: snapshot,
                configuration: configuration,
                buildDurationMs: buildDurationMs
            )
            scheduleDeferredFeedApplyFlush()
            return
        }
        performBuiltSnapshotApply(
            snapshot,
            configuration: configuration,
            buildDurationMs: buildDurationMs
        )
    }

    func flushDeferredFeedApplyIfNeeded() {
        guard let deferred = deferredFeedApply else { return }
        deferredFeedApply = nil
        deferredFeedApplyGeneration &+= 1
        performBuiltSnapshotApply(
            deferred.snapshot,
            configuration: deferred.configuration,
            buildDurationMs: deferred.buildDurationMs
        )
    }

    private func scheduleDeferredFeedApplyFlush() {
        deferredFeedApplyGeneration &+= 1
        let generation = deferredFeedApplyGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + fireTopicDetailDeferredSnapshotFlushMs) { [weak self] in
            guard let self, self.deferredFeedApplyGeneration == generation else { return }
            self.flushDeferredFeedApplyIfNeeded()
        }
    }

    private func performBuiltSnapshotApply(
        _ snapshot: FireTopicDetailPageSnapshot,
        configuration: FireTopicDetailRuntimeConfiguration,
        buildDurationMs: Int64
    ) {
        deferredFeedApply = nil
        let applyStartedAt = Date()
        lastFeedSnapshot = FireTopicDetailRuntimeSnapshot(
            items: snapshot.items,
            replyIndexByPostID: snapshot.replyIndexByPostID
        )
        feedUpdatePipeline.apply(snapshot: snapshot, configuration: configuration)
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

}
