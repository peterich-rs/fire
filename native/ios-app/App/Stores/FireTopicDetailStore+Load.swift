import Foundation

@MainActor
extension FireTopicDetailStore {
    func loadTopicDetail(
        topicId: UInt64,
        topicSlug: String? = nil,
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        rememberTopicRecoverySlug(topicSlug, topicId: topicId)
        if loadingTopicIDs.contains(topicId) {
            appViewModel.topicDetailLogger()?.debug(
                "topic detail load ignored already loading topic_id=\(topicId) force=\(force) target_post=\(targetPostNumber.map(String.init) ?? "nil")"
            )
            return
        }
        if !appViewModel.session.readiness.canReadAuthenticatedApi {
            appViewModel.topicDetailLogger()?.notice(
                "topic detail load paused unauthenticated topic_id=\(topicId) force=\(force) target_post=\(targetPostNumber.map(String.init) ?? "nil")"
            )
            applySession(appViewModel.session)
            return
        }

        if let targetPostNumber {
            setPendingScrollTarget(targetPostNumber, topicId: topicId)
        }

        var currentForce = force
        let allowsSuggestedUnreadRootScrollTarget = targetPostNumber == nil && topicDetails[topicId] == nil
        while true {
            if !currentForce,
               topicSourceSnapshots[topicId] != nil,
               targetPostNumber == nil || detailContainsPostNumber(topicId: topicId, postNumber: targetPostNumber) {
                appViewModel.topicDetailLogger()?.debug(
                    "topic detail load using cached source topic_id=\(topicId) target_post=\(targetPostNumber.map(String.init) ?? "nil")"
                )
                updateTopicErrorMessage(nil, topicId: topicId)
                return
            }

            appViewModel.topicDetailLogger()?.debug(
                "loading topic detail source topic_id=\(topicId) force=\(currentForce) target_post=\(String(describing: targetPostNumber))"
            )
            do {
                setLoadingTopic(true, topicId: topicId)
                defer { setLoadingTopic(false, topicId: topicId) }
                let sessionStore = try await appViewModel.sessionStoreValue()
                updateTopicErrorMessage(nil, topicId: topicId)
                let payload = try await fetchTopicDetailPagePayload(
                    topicId: topicId,
                    targetPostNumber: targetPostNumber,
                    trackVisit: true,
                    forceLoad: currentForce || force,
                    allowsSuggestedUnreadRootScrollTarget: allowsSuggestedUnreadRootScrollTarget,
                    sessionStore: sessionStore,
                    tracksInitialLoadAPM: true
                )
                await applyTopicDetailPagePayload(
                    payload,
                    detailNotice: nil,
                    topicId: topicId,
                    allowsSuggestedUnreadRootScrollTarget: allowsSuggestedUnreadRootScrollTarget
                )
                appViewModel.topicDetailLogger()?.debug(
                    "loaded topic detail source topic_id=\(topicId) loaded_posts=\(payload.sourceSnapshot.loadedPosts.count) reply_rows=\(payload.treePresentation.replyRows.count) source_cursor_present=\(payload.sourceSnapshot.sourceCursor != nil)"
                )
                return
            } catch {
                appViewModel.topicDetailLogger()?.error(
                    "topic detail load failed topic_id=\(topicId) error=\(error.localizedDescription)"
                )
                if await appViewModel.attemptReadPathLoginRecovery(
                    operation: "加载话题详情",
                    error: error
                ) {
                    currentForce = true
                    continue
                }
                if !currentForce,
                   case FireUniFfiError.StaleSessionResponse = error {
                    appViewModel.topicDetailLogger()?.notice(
                        "retrying stale topic detail response topic_id=\(topicId)"
                    )
                    currentForce = true
                    continue
                }
                if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                    if topicDetails[topicId] == nil {
                        updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
                    }
                    return
                }
                updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
                return
            }
        }
    }

    func fetchTopicDetailPagePayload(
        topicId: UInt64,
        targetPostNumber: UInt32?,
        trackVisit: Bool,
        forceLoad: Bool,
        allowsSuggestedUnreadRootScrollTarget: Bool = false,
        sessionStore: FireSessionStore,
        tracksInitialLoadAPM: Bool
    ) async throws -> FireTopicDetailPagePayload {
        let operation = tracksInitialLoadAPM ? "加载话题详情" : "刷新话题详情"
        let recoveryURL = topicCloudflareRecoveryURL(topicId: topicId)
        return try await performWithTimeout(30, operation: operation) { [appViewModel] in
            let fetchOperation = {
                try await appViewModel.performWithCloudflareRecovery(
                    operation: operation,
                    originURL: recoveryURL
                ) {
                    let fetchStartedAt = Date()
                    let page = try await sessionStore.fetchTopicDetailPage(
                        query: TopicDetailSourceQueryState(
                            topicId: topicId,
                            targetPostNumber: targetPostNumber,
                            allowSuggestedUnreadRoot: allowsSuggestedUnreadRootScrollTarget,
                            trackVisit: trackVisit,
                            forceLoad: forceLoad,
                            initialBatchSize: Self.topicDetailInitialBatchSize,
                            loadMoreBatchSize: Self.topicDetailLoadMoreBatchSize,
                            maxAutoBatchesPerGesture: 3,
                            maxAutoPostsPerGesture: 120
                        )
                    )
                    appViewModel.topicDetailLogger()?.debug(
                        "topic detail page ffi topic_id=\(topicId) ffi_page_ms=\(Self.elapsedMilliseconds(since: fetchStartedAt)) source_loaded_posts=\(page.sourceSnapshot.loadedPosts.count) body_post_included=true tree_total_loaded_post_count=\(page.treePresentation.totalLoadedPostCount) reply_rows=\(page.treePresentation.replyRows.count) cooked_byte_count=\(Self.cookedByteCount(sourceSnapshot: page.sourceSnapshot))"
                    )
                    return FireTopicDetailPagePayload(
                        sourceSnapshot: page.sourceSnapshot,
                        treePresentation: page.treePresentation
                    )
                }
            }
            if tracksInitialLoadAPM {
                return try await FireAPMManager.shared.withSpan(
                    .topicDetailInitialLoad,
                    metadata: ["topic_id": String(topicId)]
                ) {
                    try await fetchOperation()
                }
            }
            return try await fetchOperation()
        }
    }

    func detailContainsPostNumber(topicId: UInt64, postNumber: UInt32?) -> Bool {
        guard let postNumber else { return true }
        return topicDetails[topicId]?.postStream.posts.contains(where: { $0.postNumber == postNumber }) == true
    }

    func rememberTopicRecoverySlug(_ topicSlug: String?, topicId: UInt64) {
        let trimmedSlug = topicSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedSlug.isEmpty else {
            return
        }
        topicRecoverySlugsByTopic[topicId] = trimmedSlug
    }

    func bestKnownTopicRecoverySlug(topicId: UInt64) -> String? {
        let candidates = [
            topicSourceSnapshots[topicId]?.header.slug,
            topicDetails[topicId]?.slug,
            topicRecoverySlugsByTopic[topicId],
        ]
        for candidate in candidates {
            let trimmedSlug = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedSlug.isEmpty {
                return trimmedSlug
            }
        }
        return nil
    }

    func topicCloudflareRecoveryURL(topicId: UInt64) -> URL {
        appViewModel.cloudflareRecoveryTopicURL(
            topicId: topicId,
            topicSlug: bestKnownTopicRecoverySlug(topicId: topicId)
        )
    }

    func synthesizedTopicDetail(
        sourceSnapshot: TopicDetailSourceSnapshotState,
        treePresentation: TopicTreePresentationState
    ) -> TopicDetailState {
        Self.synthesizedTopicDetail(
            sourceSnapshot: sourceSnapshot,
            treePresentation: treePresentation
        )
    }

    /// Pure topic-detail synthesis — safe to run off the main actor.
    nonisolated static func synthesizedTopicDetail(
        sourceSnapshot: TopicDetailSourceSnapshotState,
        treePresentation: TopicTreePresentationState
    ) -> TopicDetailState {
        let replyRows = FireTopicPresentation
            .uniqueTreeRowsPreservingOrder(treePresentation.replyRows)
            .filter { row in
                row.postId != sourceSnapshot.body.post.id
            }
        let postsByID = FireTopicPresentation.topicPostsByID(
            [sourceSnapshot.body.post] + sourceSnapshot.loadedPosts
        )
        let posts = FireTopicPresentation.uniqueTopicPostsPreservingOrder(
            [sourceSnapshot.body.post] + replyRows.compactMap { postsByID[$0.postId] }
        )
        return TopicDetailState(
            id: sourceSnapshot.header.topicId,
            messageBusLastId: sourceSnapshot.header.messageBusLastId,
            title: sourceSnapshot.header.title,
            slug: sourceSnapshot.header.slug,
            postsCount: sourceSnapshot.header.postsCount,
            replyCount: sourceSnapshot.header.replyCount,
            categoryId: sourceSnapshot.header.categoryId,
            tags: sourceSnapshot.header.tags,
            views: sourceSnapshot.header.views,
            likeCount: sourceSnapshot.header.likeCount,
            createdAt: sourceSnapshot.header.createdAt,
            highestPostNumber: sourceSnapshot.header.highestPostNumber,
            lastReadPostNumber: sourceSnapshot.header.lastReadPostNumber,
            bookmarks: sourceSnapshot.header.bookmarks,
            bookmarked: sourceSnapshot.header.bookmarked,
            bookmarkId: sourceSnapshot.header.bookmarkId,
            bookmarkName: sourceSnapshot.header.bookmarkName,
            bookmarkReminderAt: sourceSnapshot.header.bookmarkReminderAt,
            acceptedAnswer: sourceSnapshot.header.acceptedAnswer,
            hasAcceptedAnswer: sourceSnapshot.header.hasAcceptedAnswer,
            canVote: sourceSnapshot.header.canVote,
            voteCount: sourceSnapshot.header.voteCount,
            userVoted: sourceSnapshot.header.userVoted,
            summarizable: sourceSnapshot.header.summarizable,
            hasCachedSummary: sourceSnapshot.header.hasCachedSummary,
            hasSummary: sourceSnapshot.header.hasSummary,
            archetype: sourceSnapshot.header.archetype,
            postStream: TopicPostStreamState(
                posts: posts,
                stream: posts.map(\.id)
            ),
            details: sourceSnapshot.header.details
        )
    }

    /// Dedup/filter tree rows + synthesize detail/lookup off-main so the main actor
    /// only commits state and kicks render/UI work.
    nonisolated static func prepareTopicDetailPagePayload(
        _ payload: FireTopicDetailPagePayload,
        allowsSuggestedUnreadRootScrollTarget: Bool
    ) -> FirePreparedTopicDetailPage {
        var treePresentation = payload.treePresentation
        treePresentation.replyRows = FireTopicPresentation
            .uniqueTreeRowsPreservingOrder(treePresentation.replyRows)
            .filter { $0.postId != payload.sourceSnapshot.body.post.id }

        let detail = synthesizedTopicDetail(
            sourceSnapshot: payload.sourceSnapshot,
            treePresentation: treePresentation
        )
        let postLookup = FireTopicPresentation.topicPostsByID(detail.postStream.posts)

        let suggestedUnreadRootPostNumber: UInt32?
        if allowsSuggestedUnreadRootScrollTarget,
           let suggestedTarget = treePresentation.firstUnreadRootPostNumber,
           suggestedTarget > 1 {
            suggestedUnreadRootPostNumber = suggestedTarget
        } else {
            suggestedUnreadRootPostNumber = nil
        }

        return FirePreparedTopicDetailPage(
            treePresentation: treePresentation,
            detail: detail,
            postLookup: postLookup,
            suggestedUnreadRootPostNumber: suggestedUnreadRootPostNumber
        )
    }

    func applyTopicDetailPagePayload(
        _ payload: FireTopicDetailPagePayload,
        detailNotice: FireTopicDetailStatusMessage?,
        topicId: UInt64,
        allowsSuggestedUnreadRootScrollTarget: Bool = false
    ) async {
        let applyStartedAt = Date()
        let prepared = await Task.detached(priority: .userInitiated) {
            Self.prepareTopicDetailPagePayload(
                payload,
                allowsSuggestedUnreadRootScrollTarget: allowsSuggestedUnreadRootScrollTarget
            )
        }.value

        if let suggestedTarget = prepared.suggestedUnreadRootPostNumber,
           topicDetailTargetPostNumbers[topicId] == nil {
            setPendingScrollTarget(suggestedTarget, topicId: topicId)
        }
        rememberTopicRecoverySlug(payload.sourceSnapshot.header.slug, topicId: topicId)
        updateTopicDetailNotice(detailNotice, topicId: topicId)
        topicSourceSnapshots[topicId] = payload.sourceSnapshot
        topicTreePresentations[topicId] = prepared.treePresentation
        if let cursor = payload.sourceSnapshot.sourceCursor {
            topicSourceCursorsByTopic[topicId] = cursor
        } else {
            topicSourceCursorsByTopic.removeValue(forKey: topicId)
        }
        setLoadMoreTopicPostsError(nil, topicId: topicId)
        topicPostLookups[topicId] = prepared.postLookup

        appViewModel.topicDetailLogger()?.debug(
            "topic detail page main apply topic_id=\(topicId) main_apply_ms=\(Self.elapsedMilliseconds(since: applyStartedAt)) source_loaded_posts=\(payload.sourceSnapshot.loadedPosts.count) body_post_included=true tree_total_loaded_post_count=\(prepared.treePresentation.totalLoadedPostCount) reply_rows=\(prepared.treePresentation.replyRows.count) cooked_byte_count=\(Self.cookedByteCount(sourceSnapshot: payload.sourceSnapshot))"
        )
        _ = await buildTopicDetailRenderUpdate(detail: prepared.detail, topicId: topicId)
        appViewModel.patchHomeTopicCounts(from: prepared.detail)
        loadTopicAiSummaryIfNeeded(topicId: topicId, detail: prepared.detail)
    }

    func loadNextTopicSourcePage(
        topicId: UInt64,
        cursor: TopicSourceCursorState
    ) async {
        guard let sessionStore = try? await appViewModel.sessionStoreValue() else {
            return
        }

        do {
            let outcome = try await appViewModel.performWithCloudflareRecovery(
                operation: "加载更多帖子",
                originURL: topicCloudflareRecoveryURL(topicId: topicId)
            ) {
                try await sessionStore.loadMoreTopicPosts(
                    query: LoadMoreTopicPostsQueryState(cursor: cursor)
                )
            }
            guard topicSourceCursorsByTopic[topicId] == cursor else {
                return
            }

            setLoadMoreTopicPostsError(nil, topicId: topicId)
            guard let currentSnapshot = topicSourceSnapshots[topicId] else {
                return
            }
            await applyTopicDetailPagePayload(
                FireTopicDetailPagePayload(
                    sourceSnapshot: Self.snapshotByAppending(
                        outcome.appendedPosts,
                        loadedRanges: outcome.loadedRanges,
                        sourceCursor: outcome.sourceCursor,
                        sourceExhausted: outcome.sourceExhausted,
                        onto: currentSnapshot
                    ),
                    treePresentation: outcome.treePresentation
                ),
                detailNotice: nil,
                topicId: topicId
            )
        } catch {
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            setLoadMoreTopicPostsError(error.localizedDescription, topicId: topicId)
        }
    }

    @discardableResult
    func loadMoreTopicPostsIfNeeded(topicId: UInt64) -> Bool {
        enqueueNextTopicSourcePageLoad(topicId: topicId)
    }

    @discardableResult
    func enqueueNextTopicSourcePageLoad(topicId: UInt64) -> Bool {
        guard let cursor = topicSourceCursorsByTopic[topicId] else {
            return false
        }
        guard Self.canStartNextTopicSourcePageLoad(
            hasMoreTopicPosts: true,
            isLoadingMoreTopicPosts: loadingMoreTopicPostIDs.contains(topicId),
            hasPendingPreloadTask: topicPostPreloadTasks[topicId] != nil,
            hasLoadedDetail: topicDetails[topicId] != nil
        ) else { return false }

        setLoadMoreTopicPostsError(nil, topicId: topicId)
        setLoadingMoreTopicPosts(true, topicId: topicId)
        topicPostPreloadTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.topicPostPreloadTasks[topicId] = nil
                self.setLoadingMoreTopicPosts(false, topicId: topicId)
            }
            await self.loadNextTopicSourcePage(topicId: topicId, cursor: cursor)
        }
        return true
    }

    func handleVisiblePostNumbersChanged(
        topicId: UInt64,
        visiblePostNumbers: Set<UInt32>
    ) {
        guard !visiblePostNumbers.isEmpty else { return }

        guard topicWindowStates[topicId] != nil else {
            return
        }

        pendingVisiblePostNumbersByTopic[topicId] = visiblePostNumbers
        topicVisibleRangeTasks[topicId]?.cancel()
        topicVisibleRangeTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: Self.topicPostVisibleRangeDebounce)
            } catch {
                return
            }

            let latestVisiblePostNumbers =
                self.pendingVisiblePostNumbersByTopic.removeValue(forKey: topicId)
                ?? visiblePostNumbers
            self.topicVisibleRangeTasks[topicId] = nil
            await self.expandRequestedRangeIfNeeded(
                topicId: topicId,
                visiblePostNumbers: latestVisiblePostNumbers
            )
        }
    }

    func needsAnchoredReload(
        detail: TopicDetailState?,
        anchorPostNumber: UInt32?,
        window: FireTopicDetailWindowState?
    ) -> Bool {
        guard let anchorPostNumber else { return detail == nil }
        guard detail != nil, let window else { return true }
        return !window.loadedPostNumbers.contains(anchorPostNumber)
    }

    func prepareTopicDetail(
        _ detail: TopicDetailState,
        topicId: UInt64
    ) -> TopicDetailState {
        var preparedDetail = detail
        let stream = FireTopicPresentation.uniqueTopicPostIDsPreservingOrder(detail.postStream.stream)
        preparedDetail.postStream = TopicPostStreamState(
            posts: FireTopicPresentation.mergeTopicPosts(
                existing: detail.postStream.posts,
                incoming: [],
                orderedPostIDs: stream
            ),
            stream: stream
        )
        topicPostLookups[topicId] = FireTopicPresentation.topicPostsByID(
            preparedDetail.postStream.posts
        )

        return preparedDetail
    }

    func cacheTopicDetail(
        _ detail: TopicDetailState,
        topicId: UInt64
    ) -> TopicDetailState {
        let cachedDetail = prepareTopicDetail(detail, topicId: topicId)
        _ = setTopicDetail(cachedDetail, topicId: topicId)

        scheduleTopicRenderCacheUpdate(detail: cachedDetail, topicId: topicId)
        return cachedDetail
    }

    @discardableResult
    func setTopicDetail(
        _ detail: TopicDetailState,
        topicId: UInt64,
        bumpRevision: Bool = true
    ) -> Bool {
        let feedToken = FireTopicDetailFeedContentToken(detail: detail)
        let chromeToken = FireTopicDetailChromeContentToken(detail: detail)
        let feedChanged = topicDetailFeedContentTokens[topicId] != feedToken
        let chromeChanged = topicDetailChromeContentTokens[topicId] != chromeToken
        let changed = feedChanged || chromeChanged
        if changed {
            topicDetails[topicId] = detail
            topicDetailFeedContentTokens[topicId] = feedToken
            topicDetailChromeContentTokens[topicId] = chromeToken
            if bumpRevision, feedChanged {
                bumpTopicCollectionRevision(topicId: topicId)
            }
            if chromeChanged {
                bumpTopicChromeRevision(topicId: topicId)
            }
        }
        return changed
    }

    func rebuildTopicDetail(
        sourceSnapshot: TopicDetailSourceSnapshotState,
        treePresentation: TopicTreePresentationState,
        topicId: UInt64
    ) -> TopicDetailState {
        let detail = synthesizedTopicDetail(
            sourceSnapshot: sourceSnapshot,
            treePresentation: treePresentation
        )
        topicPostLookups[topicId] = FireTopicPresentation.topicPostsByID(
            detail.postStream.posts
        )

        return detail
    }

    @discardableResult
    func buildTopicDetailRenderUpdate(
        detail: TopicDetailState,
        topicId: UInt64
    ) async -> TopicDetailState {
        let cachedDetail = prepareTopicDetail(detail, topicId: topicId)
        let previousRenderCache = topicRenderCaches[topicId]
        let baseURLString = renderBaseURLString
        let generation = topicRenderGenerations[topicId, default: 0] &+ 1
        topicRenderGenerations[topicId] = generation

        topicRenderTasks[topicId]?.cancel()
        let renderTask = Task { [weak self] in
            let renderResult = await Task.detached(priority: .userInitiated) {
                let renderStartedAt = Date()
                let renderCache = FireTopicPresentation.detailRenderCache(
                    from: cachedDetail,
                    baseURLString: baseURLString,
                    previous: previousRenderCache
                )
                return (
                    renderCache: renderCache,
                    renderCacheMs: Self.elapsedMilliseconds(since: renderStartedAt)
                )
            }.value

            guard !Task.isCancelled else {
                return
            }

            await self?.applyTopicDetailRenderUpdate(
                detail: cachedDetail,
                renderCache: renderResult.renderCache,
                renderCacheMs: renderResult.renderCacheMs,
                topicId: topicId,
                generation: generation
            )
        }

        topicRenderTasks[topicId] = renderTask
        await renderTask.value
        return cachedDetail
    }

    func applyTopicDetailRenderUpdate(
        detail: TopicDetailState,
        renderCache: FireTopicDetailRenderCache,
        renderCacheMs: Int64,
        topicId: UInt64,
        generation: UInt64
    ) {
        guard topicRenderGenerations[topicId] == generation else {
            return
        }

        topicRenderTasks[topicId] = nil

        let previousRenderCache = topicRenderCaches[topicId]
        let didUpdateDetail = setTopicDetail(
            detail,
            topicId: topicId,
            bumpRevision: false
        )
        let didRepairRenderState = !Self.renderStateCoversRowInputs(
            topicRenderStates[topicId],
            rowInputs: renderCache.rowInputs,
            originalPostID: renderCache.rowInputs.first?.postID
        ) && Self.renderStateCoversRowInputs(
            renderCache.renderState,
            rowInputs: renderCache.rowInputs,
            originalPostID: renderCache.rowInputs.first?.postID
        )
        let didUpdateRenderState =
            previousRenderCache?.baseURLString != renderCache.baseURLString
            || previousRenderCache?.rowInputs != renderCache.rowInputs
            || previousRenderCache?.contentInputsByPostID != renderCache.contentInputsByPostID
            || didRepairRenderState

        topicRenderCaches[topicId] = renderCache
        if didUpdateRenderState {
            topicRenderStates[topicId] = renderCache.renderState
        }
        if didUpdateDetail || didUpdateRenderState {
            bumpTopicCollectionRevision(topicId: topicId)
        }
        appViewModel.topicDetailLogger()?.debug(
            "topic detail render cache topic_id=\(topicId) render_cache_ms=\(renderCacheMs) row_input_count=\(renderCache.rowInputs.count) content_input_count=\(renderCache.contentInputsByPostID.count) did_update_detail=\(didUpdateDetail) did_update_render_state=\(didUpdateRenderState)"
        )
    }

    func scheduleTopicRenderCacheUpdate(
        detail: TopicDetailState,
        topicId: UInt64
    ) {
        let previousRenderCache = topicRenderCaches[topicId]
        let baseURLString = renderBaseURLString
        let generation = topicRenderGenerations[topicId, default: 0] &+ 1
        topicRenderGenerations[topicId] = generation

        topicRenderTasks[topicId]?.cancel()
        topicRenderTasks[topicId] = Task { [weak self] in
            let renderResult = await Task.detached(priority: .userInitiated) {
                let renderStartedAt = Date()
                let renderCache = FireTopicPresentation.detailRenderCache(
                    from: detail,
                    baseURLString: baseURLString,
                    previous: previousRenderCache
                )
                return (
                    renderCache: renderCache,
                    renderCacheMs: Self.elapsedMilliseconds(since: renderStartedAt)
                )
            }.value

            guard !Task.isCancelled else {
                return
            }

            await self?.applyTopicRenderCache(
                renderResult.renderCache,
                renderCacheMs: renderResult.renderCacheMs,
                topicId: topicId,
                generation: generation
            )
        }
    }

    func applyTopicRenderCache(
        _ renderCache: FireTopicDetailRenderCache,
        renderCacheMs: Int64,
        topicId: UInt64,
        generation: UInt64
    ) {
        guard topicRenderGenerations[topicId] == generation else {
            return
        }

        topicRenderTasks[topicId] = nil

        let previousRenderCache = topicRenderCaches[topicId]
        topicRenderCaches[topicId] = renderCache

        let didRepairRenderState = !Self.renderStateCoversRowInputs(
            topicRenderStates[topicId],
            rowInputs: renderCache.rowInputs,
            originalPostID: renderCache.rowInputs.first?.postID
        ) && Self.renderStateCoversRowInputs(
            renderCache.renderState,
            rowInputs: renderCache.rowInputs,
            originalPostID: renderCache.rowInputs.first?.postID
        )
        let didUpdateRenderState =
            previousRenderCache?.baseURLString != renderCache.baseURLString
            || previousRenderCache?.rowInputs != renderCache.rowInputs
            || previousRenderCache?.contentInputsByPostID != renderCache.contentInputsByPostID
            || didRepairRenderState
        if didUpdateRenderState {
            topicRenderStates[topicId] = renderCache.renderState
            bumpTopicCollectionRevision(topicId: topicId)
        }
        appViewModel.topicDetailLogger()?.debug(
            "topic detail render cache topic_id=\(topicId) render_cache_ms=\(renderCacheMs) row_input_count=\(renderCache.rowInputs.count) content_input_count=\(renderCache.contentInputsByPostID.count) did_update_detail=false did_update_render_state=\(didUpdateRenderState)"
        )
    }

    func applyTopicDetail(
        _ incomingDetail: TopicDetailState,
        topicId: UInt64,
        seededExhaustedPostIDs: Set<UInt64> = []
    ) {
        var detail = incomingDetail
        if let previousDetail = topicDetails[topicId] {
            detail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
                existing: previousDetail.postStream.posts,
                incoming: detail.postStream.posts,
                orderedPostIDs: detail.postStream.stream
            )
        }
        detail = cacheTopicDetail(detail, topicId: topicId)

        refreshTopicWindowState(
            topicId: topicId,
            detail: detail,
            anchorPostNumber: activeAnchorPostNumber(topicId: topicId),
            requestedRange: topicWindowStates[topicId]?.requestedRange,
            pendingScrollTarget: topicWindowStates[topicId]?.pendingScrollTarget
                ?? topicDetailTargetPostNumbers[topicId]
        )

        if !seededExhaustedPostIDs.isEmpty {
            topicWindowStates[topicId]?.exhaustedPostIDs.formUnion(seededExhaustedPostIDs)
        }

        if hasMissingPostsInRequestedRange(topicId: topicId) {
            Task {
                await hydrateTopicPostsToTargetIfNeeded(topicId: topicId)
            }
        }

        loadTopicAiSummaryIfNeeded(topicId: topicId, detail: detail)
    }

    func reloadTopicAiSummary(topicId: UInt64) {
        guard let detail = topicDetails[topicId] else { return }
        loadTopicAiSummaryIfNeeded(topicId: topicId, detail: detail, force: true)
    }

    func loadTopicAiSummaryIfNeeded(
        topicId: UInt64,
        detail: TopicDetailState,
        force: Bool = false
    ) {
        guard detail.summarizable || detail.hasCachedSummary || detail.hasSummary else {
            return
        }
        guard force
            || topicAiSummaries[topicId] == nil
                && !loadingTopicAiSummaryIDs.contains(topicId)
                && !unavailableTopicAiSummaryIDs.contains(topicId) else {
            return
        }

        topicAiSummaryTasks[topicId]?.cancel()
        _ = unavailableTopicAiSummaryIDs.remove(topicId)
        _ = topicAiSummaryErrorsByTopicID.removeValue(forKey: topicId)
        setLoadingTopicAiSummary(true, topicId: topicId)

        topicAiSummaryTasks[topicId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.setLoadingTopicAiSummary(false, topicId: topicId)
                self.topicAiSummaryTasks.removeValue(forKey: topicId)
            }

            do {
                let sessionStore = try await self.appViewModel.sessionStoreValue()
                let summary = try await self.appViewModel.performWithCloudflareRecovery(
                    operation: "加载 AI 摘要",
                    originURL: self.topicCloudflareRecoveryURL(topicId: topicId)
                ) {
                    try await sessionStore.fetchTopicAiSummary(
                        topicID: topicId,
                        skipAgeCheck: false
                    )
                }

                if let summary,
                   !summary.summarizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let didChangeSummary = self.topicAiSummaries[topicId] != summary
                    self.topicAiSummaries[topicId] = summary
                    _ = self.unavailableTopicAiSummaryIDs.remove(topicId)
                    _ = self.topicAiSummaryErrorsByTopicID.removeValue(forKey: topicId)
                    // Only publish when a real summary card becomes available or changes.
                    if didChangeSummary {
                        self.bumpTopicSidecarRevision(topicId: topicId)
                    }
                } else {
                    let removedSummary = self.topicAiSummaries.removeValue(forKey: topicId) != nil
                    _ = self.unavailableTopicAiSummaryIDs.insert(topicId)
                    // Missing summaries stay invisible; only bump if a previous card disappears.
                    if removedSummary {
                        self.bumpTopicSidecarRevision(topicId: topicId)
                    }
                }
            } catch {
                if await self.appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                    self.appViewModel.topicDetailLogger()?.notice(
                        "recoverable session error swallowed during topic AI summary load topic_id=\(topicId)"
                    )
                    return
                }
                // Failures stay silent in the feed to avoid layout jitter for the common no-summary path.
                self.topicAiSummaryErrorsByTopicID[topicId] = error.localizedDescription
                self.appViewModel.topicDetailLogger()?.error(
                    "topic AI summary load failed topic_id=\(topicId) error=\(error.localizedDescription)"
                )
            }
        }
    }

    func prehydrateAnchoredContextBeforeDisplayIfNeeded(
        detail: TopicDetailState,
        topicId: UInt64,
        anchorPostNumber: UInt32?,
        previousWindow: FireTopicDetailWindowState?,
        pendingScrollTarget: UInt32?,
        sessionStore: FireSessionStore
    ) async throws -> (detail: TopicDetailState, exhaustedPostIDs: Set<UInt64>) {
        guard anchorPostNumber != nil || pendingScrollTarget != nil else {
            return (detail, previousWindow?.exhaustedPostIDs ?? [])
        }

        let window = resolvedTopicWindowState(
            detail: detail,
            previousWindow: previousWindow,
            anchorPostNumber: anchorPostNumber,
            requestedRange: previousWindow?.requestedRange,
            pendingScrollTarget: pendingScrollTarget
        )
        let missingPostIDs = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: detail.postStream.stream,
            in: window.requestedRange,
            loadedPostIDs: Set(detail.postStream.posts.map(\.id)),
            excluding: window.exhaustedPostIDs
        )
        guard !missingPostIDs.isEmpty else {
            return (detail, window.exhaustedPostIDs)
        }

        let recoveryURL = topicCloudflareRecoveryURL(topicId: topicId)
        return try await Self.hydrateRequestedRange(
            detail: detail,
            window: window
        ) { [appViewModel] batchPostIDs in
            try await appViewModel.performWithCloudflareRecovery(
                operation: "加载更多帖子",
                originURL: recoveryURL
            ) {
                try await sessionStore.fetchTopicPosts(
                    topicID: topicId,
                    postIDs: batchPostIDs
                )
            }
        }
    }

    func expandRequestedRangeIfNeeded(
        topicId: UInt64,
        visiblePostNumbers: Set<UInt32>
    ) async {
        guard let detail = topicDetails[topicId],
              var window = topicWindowStates[topicId] else {
            return
        }

        let previousRange = window.requestedRange
        let visibleIndices = visiblePostNumbers.compactMap { postNumber in
            streamIndex(forPostNumber: postNumber, in: detail)
        }

        if let minVisibleIndex = visibleIndices.min(),
           let maxVisibleIndex = visibleIndices.max() {
            let shouldExpandBackward = window.requestedRange.lowerBound > 0
                && minVisibleIndex <= window.requestedRange.lowerBound + Self.topicPostPrefetchThreshold
            let shouldExpandForward = window.requestedRange.upperBound < detail.postStream.stream.count
                && maxVisibleIndex >= max(
                    window.requestedRange.lowerBound,
                    window.requestedRange.upperBound - Self.topicPostPrefetchThreshold - 1
                )

            if shouldExpandBackward || shouldExpandForward {
                window.requestedRange = Self.expandedRequestedRange(
                    current: window.requestedRange,
                    totalCount: detail.postStream.stream.count,
                    expandBackward: shouldExpandBackward,
                    expandForward: shouldExpandForward,
                    anchorIndex: streamIndex(forPostNumber: window.activeAnchorPostNumber, in: detail)
                )
                topicWindowStates[topicId] = window
            }
        }

        if topicWindowStates[topicId]?.requestedRange != previousRange
            || hasMissingPostsInRequestedRange(topicId: topicId) {
            await hydrateTopicPostsToTargetIfNeeded(topicId: topicId)
        }
    }

    func hydrateTopicPostsToTargetIfNeeded(topicId: UInt64) async {
        guard let sessionStore = appViewModel.currentSessionStore() else {
            return
        }
        guard !Task.isCancelled else {
            return
        }
        guard !loadingMoreTopicPostIDs.contains(topicId) else {
            return
        }
        guard hydratingTopicPostIDs.insert(topicId).inserted else {
            return
        }
        defer { hydratingTopicPostIDs.remove(topicId) }

        await FireAPMManager.shared.withSpan(
            .topicDetailHydration,
            metadata: ["topic_id": String(topicId)]
        ) {
            var hydratedPosts: [TopicPostState] = []
            var hydratedPostIDs: Set<UInt64> = []
            var exhaustedPostIDs: Set<UInt64> = []
            var iterationCount = 0

            while !Task.isCancelled {
                iterationCount &+= 1
                if iterationCount > Self.topicPostHydrationIterationLimit {
                    if !hydratedPosts.isEmpty || !exhaustedPostIDs.isEmpty {
                        await applyHydratedTopicPostsIfNeeded(
                            topicId: topicId,
                            posts: hydratedPosts,
                            exhaustedPostIDs: exhaustedPostIDs
                        )
                    }
                    appViewModel.topicDetailLogger()?.warning(
                        "topic post hydration hit iteration limit topic_id=\(topicId) iterations=\(iterationCount - 1)"
                    )
                    return
                }

                guard let detail = topicDetails[topicId],
                      let window = topicWindowStates[topicId] else {
                    return
                }

                let missingPostIDs = FireTopicPresentation.missingPostIDs(
                    orderedPostIDs: detail.postStream.stream,
                    in: window.requestedRange,
                    loadedPostIDs: Set(detail.postStream.posts.map(\.id)).union(hydratedPostIDs),
                    excluding: window.exhaustedPostIDs.union(exhaustedPostIDs)
                )
                guard !missingPostIDs.isEmpty else {
                    if !hydratedPosts.isEmpty || !exhaustedPostIDs.isEmpty {
                        await applyHydratedTopicPostsIfNeeded(
                            topicId: topicId,
                            posts: hydratedPosts,
                            exhaustedPostIDs: exhaustedPostIDs
                        )
                        hydratedPosts.removeAll()
                        hydratedPostIDs.removeAll()
                        exhaustedPostIDs.removeAll()
                        continue
                    }
                    if advanceRequestedRangeTowardPendingScrollTargetIfNeeded(
                        topicId: topicId,
                        detail: detail,
                        window: window
                    ) {
                        continue
                    }
                    await applyHydratedTopicPostsIfNeeded(
                        topicId: topicId,
                        posts: hydratedPosts,
                        exhaustedPostIDs: exhaustedPostIDs
                    )
                    return
                }

                let batchPostIDs = Array(missingPostIDs.prefix(Self.topicPostPageSize))

                do {
                    let fetchedPosts = try await appViewModel.performWithCloudflareRecovery(
                        operation: "加载更多帖子",
                        originURL: topicCloudflareRecoveryURL(topicId: topicId)
                    ) {
                        try await sessionStore.fetchTopicPosts(
                            topicID: topicId,
                            postIDs: batchPostIDs
                        )
                    }
                    let returnedPostIDs = Set(fetchedPosts.map(\.id))
                    exhaustedPostIDs.formUnion(
                        batchPostIDs.filter { !returnedPostIDs.contains($0) }
                    )
                    hydratedPosts.append(contentsOf: fetchedPosts)
                    hydratedPostIDs.formUnion(returnedPostIDs)
                } catch {
                    await applyHydratedTopicPostsIfNeeded(
                        topicId: topicId,
                        posts: hydratedPosts,
                        exhaustedPostIDs: exhaustedPostIDs
                    )
                    if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                        return
                    }
                    updateTopicErrorMessage(error.localizedDescription, topicId: topicId)
                    return
                }
            }

            await applyHydratedTopicPostsIfNeeded(
                topicId: topicId,
                posts: hydratedPosts,
                exhaustedPostIDs: exhaustedPostIDs
            )
        }
    }

    func advanceRequestedRangeTowardPendingScrollTargetIfNeeded(
        topicId: UInt64,
        detail: TopicDetailState,
        window: FireTopicDetailWindowState
    ) -> Bool {
        guard let target = window.pendingScrollTarget,
              !window.loadedPostNumbers.contains(target) else {
            return false
        }

        let loadedPostNumbersInWindow = loadedPostNumbers(
            in: window.requestedRange,
            detail: detail
        )
        guard let nextRange = Self.nextRequestedRangeForUnresolvedTarget(
            postNumber: target,
            current: window.requestedRange,
            totalCount: detail.postStream.stream.count,
            loadedPostNumbersInCurrentRange: loadedPostNumbersInWindow
        ), nextRange != window.requestedRange else {
            return false
        }

        topicWindowStates[topicId]?.requestedRange = nextRange
        return true
    }

    func loadedPostNumbers(
        in range: Range<Int>,
        detail: TopicDetailState
    ) -> [UInt32] {
        let stream = FireTopicPresentation.uniqueTopicPostIDsPreservingOrder(detail.postStream.stream)
        let indexByPostID = Dictionary(
            stream.enumerated().map { index, postID in
                (postID, index)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return detail.postStream.posts.compactMap { post in
            guard let index = indexByPostID[post.id],
                  range.contains(index) else {
                return nil
            }
            return post.postNumber
        }
    }

    func applyHydratedTopicPostsIfNeeded(
        topicId: UInt64,
        posts: [TopicPostState],
        exhaustedPostIDs: Set<UInt64>
    ) async {
        guard !posts.isEmpty || !exhaustedPostIDs.isEmpty else {
            return
        }
        guard var currentDetail = topicDetails[topicId],
              let currentWindow = topicWindowStates[topicId] else {
            return
        }

        topicWindowStates[topicId]?.exhaustedPostIDs.formUnion(exhaustedPostIDs)

        guard !posts.isEmpty else {
            if let target = topicWindowStates[topicId]?.pendingScrollTarget,
               isScrollTargetExhausted(topicId: topicId, postNumber: target) {
                markScrollTargetSatisfied(topicId: topicId, postNumber: target)
            }
            return
        }

        currentDetail.postStream.posts = FireTopicPresentation.mergeTopicPosts(
            existing: currentDetail.postStream.posts,
            incoming: posts,
            orderedPostIDs: currentDetail.postStream.stream
        )
        let cachedDetail = await buildTopicDetailRenderUpdate(
            detail: currentDetail,
            topicId: topicId
        )

        refreshTopicWindowState(
            topicId: topicId,
            detail: cachedDetail,
            anchorPostNumber: currentWindow.activeAnchorPostNumber,
            requestedRange: currentWindow.requestedRange,
            pendingScrollTarget: currentWindow.pendingScrollTarget
        )

        if let target = topicWindowStates[topicId]?.pendingScrollTarget,
           isScrollTargetExhausted(topicId: topicId, postNumber: target) {
            markScrollTargetSatisfied(topicId: topicId, postNumber: target)
        }
    }

    func hasMissingPostsInRequestedRange(topicId: UInt64) -> Bool {
        guard let detail = topicDetails[topicId],
              let window = topicWindowStates[topicId] else {
            return false
        }

        let missingPostIDs = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: detail.postStream.stream,
            in: window.requestedRange,
            loadedPostIDs: Set(detail.postStream.posts.map(\.id)),
            excluding: window.exhaustedPostIDs
        )
        return !missingPostIDs.isEmpty
    }

    func refreshTopicWindowState(
        topicId: UInt64,
        detail: TopicDetailState,
        anchorPostNumber: UInt32?,
        requestedRange: Range<Int>?,
        pendingScrollTarget: UInt32?
    ) {
        topicWindowStates[topicId] = resolvedTopicWindowState(
            detail: detail,
            previousWindow: topicWindowStates[topicId],
            anchorPostNumber: anchorPostNumber,
            requestedRange: requestedRange,
            pendingScrollTarget: pendingScrollTarget
        )
    }

    func resolvedTopicWindowState(
        detail: TopicDetailState,
        previousWindow: FireTopicDetailWindowState?,
        anchorPostNumber: UInt32?,
        requestedRange: Range<Int>?,
        pendingScrollTarget: UInt32?
    ) -> FireTopicDetailWindowState {
        let loadedPostNumbers = Set(detail.postStream.posts.map(\.postNumber))
        let loadedPostIDs = Set(detail.postStream.posts.map(\.id))
        var loadedIndices = IndexSet()
        for (index, postID) in detail.postStream.stream.enumerated() {
            if loadedPostIDs.contains(postID) {
                loadedIndices.insert(index)
            }
        }

        let resolvedAnchor = pendingScrollTarget ?? anchorPostNumber ?? previousWindow?.pendingScrollTarget
        let anchorIndex = streamIndex(forPostNumber: resolvedAnchor, in: detail)
        let anchorChanged = resolvedAnchor != previousWindow?.activeAnchorPostNumber
        let resolvedRequestedRange = resolveRequestedRange(
            requestedRange,
            previousWindow: previousWindow,
            totalCount: detail.postStream.stream.count,
            anchorIndex: anchorIndex,
            loadedIndices: loadedIndices,
            anchorChanged: anchorChanged
        )

        return FireTopicDetailWindowState(
            anchorPostNumber: resolvedAnchor,
            requestedRange: resolvedRequestedRange,
            loadedIndices: loadedIndices,
            loadedPostNumbers: loadedPostNumbers,
            exhaustedPostIDs: previousWindow?.exhaustedPostIDs ?? [],
            pendingScrollTarget: pendingScrollTarget
        )
    }

    func resolveRequestedRange(
        _ requestedRange: Range<Int>?,
        previousWindow: FireTopicDetailWindowState?,
        totalCount: Int,
        anchorIndex: Int?,
        loadedIndices: IndexSet,
        anchorChanged: Bool
    ) -> Range<Int> {
        guard totalCount > 0 else {
            return 0..<0
        }

        if let requestedRange {
            return clampedRequestedRange(
                requestedRange,
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        if let previousWindow, !anchorChanged {
            return clampedRequestedRange(
                previousWindow.requestedRange,
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        return Self.initialRequestedRange(
            totalCount: totalCount,
            anchorIndex: anchorIndex,
            loadedIndices: loadedIndices
        )
    }

    func clampedRequestedRange(
        _ requestedRange: Range<Int>,
        totalCount: Int,
        anchorIndex: Int?,
        loadedIndices: IndexSet
    ) -> Range<Int> {
        let clamped = requestedRange.clamped(to: 0..<totalCount)
        guard !clamped.isEmpty else {
            return Self.initialRequestedRange(
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        if let anchorIndex, !clamped.contains(anchorIndex) {
            return Self.initialRequestedRange(
                totalCount: totalCount,
                anchorIndex: anchorIndex,
                loadedIndices: loadedIndices
            )
        }

        let lowerBound = min(clamped.lowerBound, loadedIndices.first ?? clamped.lowerBound)
        let upperBound = max(clamped.upperBound, (loadedIndices.last.map { $0 + 1 }) ?? clamped.upperBound)
        return Self.boundedRequestedRange(
            lowerBound: lowerBound,
            upperBound: upperBound,
            totalCount: totalCount,
            anchorIndex: anchorIndex
        )
    }

    func streamIndex(forPostNumber postNumber: UInt32?, in detail: TopicDetailState) -> Int? {
        guard let postNumber,
              let postID = detail.postStream.posts.first(where: { $0.postNumber == postNumber })?.id else {
            return nil
        }
        return detail.postStream.stream.firstIndex(of: postID)
    }

    nonisolated static func scrollTargetIsExhausted(
        postNumber: UInt32,
        window: FireTopicDetailWindowState,
        orderedPostIDs: [UInt64],
        loadedPostIDs: Set<UInt64>
    ) -> Bool {
        if window.loadedPostNumbers.contains(postNumber) {
            return false
        }

        let hasMissingInWindow = !FireTopicPresentation.missingPostIDs(
            orderedPostIDs: orderedPostIDs,
            in: window.requestedRange,
            loadedPostIDs: loadedPostIDs,
            excluding: window.exhaustedPostIDs
        ).isEmpty
        if hasMissingInWindow {
            return false
        }

        let wholeStreamResolved = FireTopicPresentation.missingPostIDs(
            orderedPostIDs: orderedPostIDs,
            in: 0..<orderedPostIDs.count,
            loadedPostIDs: loadedPostIDs,
            excluding: window.exhaustedPostIDs
        ).isEmpty
        if window.activeAnchorPostNumber == postNumber && !wholeStreamResolved {
            return false
        }

        return true
    }

    nonisolated static func nextRequestedRangeForUnresolvedTarget(
        postNumber: UInt32,
        current: Range<Int>,
        totalCount: Int,
        loadedPostNumbersInCurrentRange: [UInt32]
    ) -> Range<Int>? {
        guard totalCount > 0 else {
            return nil
        }
        guard current.lowerBound > 0 || current.upperBound < totalCount else {
            return nil
        }

        let estimatedIndex = max(0, min(Int(postNumber) - 1, totalCount - 1))
        if !current.contains(estimatedIndex) {
            return boundedRequestedRange(
                lowerBound: estimatedIndex - (topicPostPageSize / 2),
                upperBound: estimatedIndex + (topicPostPageSize / 2) + 1,
                totalCount: totalCount,
                anchorIndex: nil
            )
        }

        let direction: FireTopicDetailSearchDirection
        if let maxLoadedPostNumber = loadedPostNumbersInCurrentRange.max(),
           postNumber > maxLoadedPostNumber {
            direction = .forward
        } else if let minLoadedPostNumber = loadedPostNumbersInCurrentRange.min(),
                  postNumber < minLoadedPostNumber {
            direction = .backward
        } else if totalCount - current.upperBound >= current.lowerBound {
            direction = .forward
        } else {
            direction = .backward
        }

        return nextDirectionalSearchRange(
            current: current,
            totalCount: totalCount,
            direction: direction
        )
    }

    nonisolated static func initialRequestedRange(
        totalCount: Int,
        anchorIndex: Int?,
        loadedIndices: IndexSet
    ) -> Range<Int> {
        guard totalCount > 0 else {
            return 0..<0
        }

        let loadedLowerBound = loadedIndices.first ?? anchorIndex ?? 0
        let loadedUpperBound = (loadedIndices.last.map { $0 + 1 }) ?? min(totalCount, loadedLowerBound + 1)
        let desiredLowerBound: Int
        if let anchorIndex {
            desiredLowerBound = anchorIndex - (topicPostPageSize / 2)
        } else {
            desiredLowerBound = min(loadedLowerBound, loadedUpperBound - topicPostPageSize)
        }

        return boundedRequestedRange(
            lowerBound: min(desiredLowerBound, loadedLowerBound),
            upperBound: max(loadedUpperBound, loadedLowerBound + topicPostPageSize),
            totalCount: totalCount,
            anchorIndex: anchorIndex
        )
    }

    nonisolated static func expandedRequestedRange(
        current: Range<Int>,
        totalCount: Int,
        expandBackward: Bool,
        expandForward: Bool,
        anchorIndex: Int?
    ) -> Range<Int> {
        let lowerBound = expandBackward ? current.lowerBound - topicPostPageSize : current.lowerBound
        let upperBound = expandForward ? current.upperBound + topicPostForwardExpansionSize : current.upperBound
        return boundedRequestedRange(
            lowerBound: lowerBound,
            upperBound: upperBound,
            totalCount: totalCount,
            anchorIndex: anchorIndex
        )
    }

    nonisolated static func boundedRequestedRange(
        lowerBound: Int,
        upperBound: Int,
        totalCount: Int,
        anchorIndex: Int?
    ) -> Range<Int> {
        guard totalCount > 0 else {
            return 0..<0
        }

        var lowerBound = max(0, min(lowerBound, totalCount))
        var upperBound = max(lowerBound, min(upperBound, totalCount))
        if lowerBound == upperBound {
            upperBound = min(totalCount, lowerBound + 1)
        }

        if upperBound - lowerBound <= FireTopicDetailWindowState.maxWindowSize {
            return lowerBound..<upperBound
        }

        if let anchorIndex {
            let maxLowerBound = max(0, totalCount - FireTopicDetailWindowState.maxWindowSize)
            let minimumLowerBound = max(0, anchorIndex - FireTopicDetailWindowState.maxWindowSize + 1)
            let maximumLowerBound = min(anchorIndex, maxLowerBound)
            lowerBound = max(minimumLowerBound, min(maximumLowerBound, lowerBound))
            upperBound = min(totalCount, lowerBound + FireTopicDetailWindowState.maxWindowSize)
            lowerBound = max(0, upperBound - FireTopicDetailWindowState.maxWindowSize)
            return lowerBound..<upperBound
        }

        upperBound = min(totalCount, lowerBound + FireTopicDetailWindowState.maxWindowSize)
        lowerBound = max(0, upperBound - FireTopicDetailWindowState.maxWindowSize)
        return lowerBound..<upperBound
    }
}
