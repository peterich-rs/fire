import Foundation

public enum FireHomeTopicListDisplayState: Hashable {
    case loading
    case blockingError(message: String)
    case empty(nonBlockingErrorMessage: String?)
    case content(nonBlockingErrorMessage: String?)

    public static func resolve(
        hasResolvedCurrentScope: Bool,
        hasRows: Bool,
        errorMessage: String?
    ) -> Self {
        if !hasResolvedCurrentScope {
            if let errorMessage {
                return .blockingError(message: errorMessage)
            }
            return .loading
        }

        if hasRows {
            return .content(nonBlockingErrorMessage: errorMessage)
        }

        return .empty(nonBlockingErrorMessage: errorMessage)
    }
}

@MainActor
final class FireHomeFeedStore: ObservableObject {
    private static let topicListRefreshLoadingPollInterval: Duration = .milliseconds(250)

    private struct FireHomeTopicRowsMergeResult {
        let rows: [FireTopicRowPresentation]
        let entities: FireEntityIndex<UInt64, FireTopicRowPresentation>
        let order: FireOrderedIDList<UInt64>
        let dirtyTopicIDs: Set<UInt64>
        let rebuildAllTokens: Bool
    }

    @Published private(set) var selectedTopicKind: TopicListKindState = .latest
    @Published private(set) var selectedHomeCategoryId: UInt64?
    @Published private(set) var selectedHomeTags: [String] = []
    @Published private(set) var topicRows: [FireTopicRowPresentation] = []
    @Published private(set) var moreTopicsUrl: String?
    @Published private(set) var nextTopicsPage: UInt32?
    @Published private(set) var allCategories: [FireTopicCategoryPresentation] = []
    @Published private(set) var topicCategories: [UInt64: FireTopicCategoryPresentation] = [:]
    @Published private(set) var topTags: [String] = []
    @Published private(set) var canTagTopics = false
    @Published private(set) var isLoadingTopics = false
    @Published private(set) var isAppendingTopics = false
    @Published private(set) var topicLoadErrorMessage: String?
    @Published private(set) var isOffline = false

    private(set) var visibleTopicIDs: Set<UInt64> = []
    private(set) var isTopicListVisible = false
    private(set) var isSceneActive = false
    private(set) var renderedTopicListScope: FireTopicListRefreshScope?
    private let appViewModel: FireAppViewModel
    private let topicListRefreshClock = ContinuousClock()
    private var pendingTopicListRefreshTask: Task<Void, Never>?
    private var filterChangeRefreshTask: Task<Void, Never>?
    private var topicListMessageBusRefreshController = FireTopicListMessageBusRefreshController()
    private var topicEntities = FireEntityIndex<UInt64, FireTopicRowPresentation>()
    private var topicOrder = FireOrderedIDList<UInt64>()
    private var topicRowContentTokensByID: [UInt64: String] = [:]

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
        applySession(appViewModel.session)
    }

    var selectedHomeCategoryPresentation: FireTopicCategoryPresentation? {
        guard let id = selectedHomeCategoryId else { return nil }
        return categoryPresentation(for: id)
    }

    var currentScopeNextTopicsPage: UInt32? {
        hasResolvedCurrentScope ? nextTopicsPage : nil
    }

    var topicListDisplayState: FireHomeTopicListDisplayState {
        FireHomeTopicListDisplayState.resolve(
            hasResolvedCurrentScope: hasResolvedCurrentScope,
            hasRows: !topicRows.isEmpty,
            errorMessage: topicLoadErrorMessage
        )
    }

    static func sanitizedVisibleTopicIDs(
        currentTopicIDs: [UInt64],
        candidateVisibleTopicIDs: Set<UInt64>
    ) -> Set<UInt64> {
        candidateVisibleTopicIDs.intersection(currentTopicIDs)
    }

    static func patchedTopicRow(
        _ row: FireTopicRowPresentation,
        from detail: TopicDetailState
    ) -> FireTopicRowPresentation? {
        guard row.topic.id == detail.id else {
            return nil
        }
        let nextHasUnreadPosts = detail.lastReadPostNumber.map { lastReadPostNumber in
            lastReadPostNumber < detail.highestPostNumber
        } ?? row.hasUnreadPosts
        let nextUnreadPosts = nextHasUnreadPosts ? row.topic.unreadPosts : 0
        let nextNewPosts = nextHasUnreadPosts ? row.topic.newPosts : 0
        guard row.topic.postsCount != detail.postsCount
            || row.topic.replyCount != detail.replyCount
            || row.topic.views != detail.views
            || row.topic.lastReadPostNumber != detail.lastReadPostNumber
            || row.topic.highestPostNumber != detail.highestPostNumber
            || row.topic.unreadPosts != nextUnreadPosts
            || row.topic.newPosts != nextNewPosts
            || row.hasUnreadPosts != nextHasUnreadPosts else {
            return nil
        }

        var patched = row
        patched.topic.postsCount = detail.postsCount
        patched.topic.replyCount = detail.replyCount
        patched.topic.views = detail.views
        patched.topic.lastReadPostNumber = detail.lastReadPostNumber
        patched.topic.highestPostNumber = detail.highestPostNumber
        patched.topic.unreadPosts = nextUnreadPosts
        patched.topic.newPosts = nextNewPosts
        patched.hasUnreadPosts = nextHasUnreadPosts
        return patched
    }

    func updateVisibleTopicIDs(_ topicIDs: Set<UInt64>) {
        visibleTopicIDs = Self.sanitizedVisibleTopicIDs(
            currentTopicIDs: topicRows.map(\.topic.id),
            candidateVisibleTopicIDs: topicIDs
        )
    }

    func setTopicListVisible(_ isVisible: Bool) {
        guard isTopicListVisible != isVisible else {
            return
        }
        isTopicListVisible = isVisible
        if !isVisible {
            cancelPendingTopicListRefresh()
        }
    }

    func setSceneActive(_ isActive: Bool) {
        guard isSceneActive != isActive else {
            return
        }
        isSceneActive = isActive
        if !isActive {
            cancelPendingTopicListRefresh()
        }
    }

    func applySession(_ session: SessionState) {
        allCategories = session.bootstrap.categories
        topicCategories = Dictionary(
            uniqueKeysWithValues: session.bootstrap.categories.map { ($0.id, $0) }
        )
        topTags = session.bootstrap.topTags
        canTagTopics = session.bootstrap.canTagTopics

        guard session.readiness.canReadAuthenticatedApi else {
            reset(resetTopicKind: true)
            return
        }
    }

    func categoryPresentation(for categoryID: UInt64?) -> FireTopicCategoryPresentation? {
        guard let categoryID else {
            return nil
        }
        return topicCategories[categoryID]
    }

    func topicRow(for topicID: UInt64) -> FireTopicRowPresentation? {
        topicEntities.entity(for: topicID)
    }

    func topicRowContentToken(for topicID: UInt64) -> String? {
        topicRowContentTokensByID[topicID]
    }

    @discardableResult
    func patchTopicCounts(from detail: TopicDetailState) -> Bool {
        guard let row = topicEntities.entity(for: detail.id),
              let patched = Self.patchedTopicRow(row, from: detail) else {
            return false
        }

        topicEntities.upsert([patched], id: \.topic.id)
        let rows = topicEntities.orderedValues(for: topicOrder)
        topicRows = rows
        updateTopicRowContentTokens(
            rows: rows,
            dirtyTopicIDs: [detail.id],
            rebuildAll: false
        )
        visibleTopicIDs = Self.sanitizedVisibleTopicIDs(
            currentTopicIDs: rows.map(\.topic.id),
            candidateVisibleTopicIDs: visibleTopicIDs
        )
        return true
    }

    func selectTopicKind(_ kind: TopicListKindState) {
        guard selectedTopicKind != kind else {
            return
        }
        selectedTopicKind = kind
        topicLoadErrorMessage = nil
        isOffline = false
        syncCurrentHomeTopicListScope()
        scheduleDebouncedRefresh()
    }

    func selectHomeCategory(_ categoryId: UInt64?) {
        guard selectedHomeCategoryId != categoryId else { return }
        selectedHomeCategoryId = categoryId
        selectedHomeTags = []
        topicLoadErrorMessage = nil
        isOffline = false
        syncCurrentHomeTopicListScope()
        scheduleDebouncedRefresh()
    }

    func addHomeTag(_ tag: String) {
        guard !selectedHomeTags.contains(tag) else { return }
        selectedHomeTags.append(tag)
        topicLoadErrorMessage = nil
        isOffline = false
        syncCurrentHomeTopicListScope()
        scheduleDebouncedRefresh()
    }

    func removeHomeTag(_ tag: String) {
        guard selectedHomeTags.contains(tag) else { return }
        selectedHomeTags.removeAll { $0 == tag }
        topicLoadErrorMessage = nil
        isOffline = false
        syncCurrentHomeTopicListScope()
        scheduleDebouncedRefresh()
    }

    func clearHomeTags() {
        guard !selectedHomeTags.isEmpty else { return }
        selectedHomeTags = []
        topicLoadErrorMessage = nil
        isOffline = false
        syncCurrentHomeTopicListScope()
        scheduleDebouncedRefresh()
    }

    func refreshTopics() {
        Task {
            await refreshTopicsAsync()
        }
    }

    func refreshTopicsAsync() async {
        await refreshTopicsIfPossible(force: true)
    }

    func applyTopicList(_ state: TopicListState) {
        let mergeResult = mergeTopicRows(
            incoming: state.rows,
            reset: true,
            usesIncrementalRefresh: false
        )
        applyTopicRows(mergeResult)
        renderedTopicListScope = currentTopicListRefreshScope
        topicLoadErrorMessage = nil
        isOffline = state.isCached
        moreTopicsUrl = state.moreTopicsUrl
        nextTopicsPage = state.nextPage
        isLoadingTopics = false
        isAppendingTopics = false
    }

    @discardableResult
    func refreshTopicsIfPossible(force: Bool) async -> Bool {
        cancelPendingTopicListRefresh()
        return await loadTopics(page: nil, reset: true, force: force, refreshMode: .full)
    }

    func loadMoreTopics() {
        guard let nextTopicsPage = currentScopeNextTopicsPage else {
            return
        }

        Task {
            await loadTopics(page: nextTopicsPage, reset: false, force: true)
        }
    }

    func handleTopicListMessageBusEvent(_ event: MessageBusEventState) {
        guard let busKind = event.topicListKind else { return }
        let scope = currentTopicListRefreshScope
        guard busKind == scope.kind else { return }

        let allowIncremental = Self.canScheduleIncrementalMessageBusRefresh(
            scope: scope,
            renderedScope: renderedTopicListScope,
            isTopicListVisible: isTopicListVisible,
            isSceneActive: isSceneActive,
            hasRows: !topicRows.isEmpty
        )
        guard let delay = topicListMessageBusRefreshController.register(
            event: event,
            for: scope,
            now: topicListRefreshClock.now,
            allowIncremental: allowIncremental
        ) else {
            return
        }

        pendingTopicListRefreshTask?.cancel()
        pendingTopicListRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard let self else { return }

            while self.isLoadingTopics {
                do {
                    try await Task.sleep(for: Self.topicListRefreshLoadingPollInterval)
                } catch {
                    return
                }
            }

            let scope = self.currentTopicListRefreshScope
            let refreshMode = self.topicListMessageBusRefreshController.takePendingRefresh(for: scope)
            self.pendingTopicListRefreshTask = nil

            guard let refreshMode else { return }
            await self.refreshTopicsFromMessageBus(refreshMode)
        }
    }

    func handleMessageBusStopped() {
        cancelPendingTopicListRefresh()
    }

    func reset(resetTopicKind: Bool = true) {
        cancelPendingTopicListRefresh()
        filterChangeRefreshTask?.cancel()
        filterChangeRefreshTask = nil
        topicEntities.removeAll()
        topicOrder.removeAll()
        topicRowContentTokensByID = [:]
        topicRows = []
        moreTopicsUrl = nil
        nextTopicsPage = nil
        isLoadingTopics = false
        isAppendingTopics = false
        topicLoadErrorMessage = nil
        isOffline = false
        renderedTopicListScope = nil
        selectedHomeCategoryId = nil
        selectedHomeTags = []
        if resetTopicKind {
            selectedTopicKind = .latest
        }
    }

    func clearTopicLoadError() {
        topicLoadErrorMessage = nil
    }

    private var currentTopicListRefreshScope: FireTopicListRefreshScope {
        FireTopicListRefreshScope(
            kind: selectedTopicKind,
            categoryId: selectedHomeCategoryId,
            tags: selectedHomeTags
        )
    }

    private func applyCurrentTopicListRefreshScope(_ scope: FireTopicListRefreshScope) {
        selectedTopicKind = scope.kind
        selectedHomeCategoryId = scope.categoryId
        selectedHomeTags = scope.tags
    }

    private var hasResolvedCurrentScope: Bool {
        renderedTopicListScope == currentTopicListRefreshScope
    }

    private func syncCurrentHomeTopicListScope() {
        let scope = currentTopicListRefreshScope
        Task { [weak self] in
            guard let self else { return }
            do {
                let sessionStore = try await appViewModel.sessionStoreValue()
                let updated = try await sessionStore.setCurrentHomeTopicListScope(scope.state)
                await MainActor.run {
                    self.applyCurrentTopicListRefreshScope(FireTopicListRefreshScope(updated))
                }
            } catch {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: "home.feed",
                    message: "failed to sync home topic list scope: \(error.localizedDescription)"
                )
            }
        }
    }

    private func scheduleDebouncedRefresh() {
        cancelPendingTopicListRefresh()
        filterChangeRefreshTask?.cancel()
        filterChangeRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.refreshTopicsIfPossible(force: true)
        }
    }

    private func refreshTopicsFromMessageBus(_ refreshMode: FireTopicListMessageBusRefreshMode) async {
        guard case .incremental = refreshMode,
              Self.canScheduleIncrementalMessageBusRefresh(
                  scope: currentTopicListRefreshScope,
                  renderedScope: renderedTopicListScope,
                  isTopicListVisible: isTopicListVisible,
                  isSceneActive: isSceneActive,
                  hasRows: !topicRows.isEmpty
              ) else {
            return
        }
        await loadTopics(page: nil, reset: true, force: true, refreshMode: refreshMode)
    }

    nonisolated static func canScheduleIncrementalMessageBusRefresh(
        scope: FireTopicListRefreshScope,
        renderedScope: FireTopicListRefreshScope?,
        isTopicListVisible: Bool,
        isSceneActive: Bool,
        hasRows: Bool
    ) -> Bool {
        isSceneActive
            && isTopicListVisible
            && hasRows
            && scope.supportsIncrementalMessageBusRefresh
            && renderedScope == scope
    }

    @discardableResult
    private func loadTopics(
        page: UInt32?,
        reset: Bool,
        force: Bool,
        refreshMode: FireTopicListMessageBusRefreshMode = .full
    ) async -> Bool {
        if !appViewModel.session.readiness.canReadAuthenticatedApi {
            self.reset(resetTopicKind: true)
            return false
        }
        if isLoadingTopics {
            return false
        }
        if reset && !force && !topicRows.isEmpty {
            return false
        }

        isLoadingTopics = true
        isAppendingTopics = !reset
        topicLoadErrorMessage = nil
        if reset {
            isOffline = false
        }
        defer {
            isLoadingTopics = false
            isAppendingTopics = false
        }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            let requestedScopeState = try await sessionStore.setCurrentHomeTopicListScope(
                currentTopicListRefreshScope.state
            )
            let requestedScope = FireTopicListRefreshScope(requestedScopeState)
            applyCurrentTopicListRefreshScope(requestedScope)
            let requestedKind = requestedScope.kind
            let categoryId = requestedScope.categoryId
            let requestedTags = requestedScope.tags
            let categorySlug = categoryId.flatMap { categoryPresentation(for: $0)?.slug }
            let parentSlug: String? = categoryId.flatMap { id in
                guard let category = categoryPresentation(for: id),
                      let parentId = category.parentCategoryId else {
                    return nil
                }
                return categoryPresentation(for: parentId)?.slug
            }
            let primaryTag = requestedTags.first
            let additionalTags = requestedTags.count > 1
                ? Array(requestedTags.dropFirst())
                : []
            let incrementalTopicIDs: [UInt64]
            switch refreshMode {
            case .full:
                incrementalTopicIDs = []
            case .incremental(let topicIDs):
                incrementalTopicIDs = topicIDs
            }
            let usesIncrementalRefresh = page == nil
                && reset
                && !incrementalTopicIDs.isEmpty
                && requestedScope.supportsIncrementalMessageBusRefresh
                && renderedTopicListScope == requestedScope
                && !topicRows.isEmpty
            let topicListQuery = TopicListQueryState(
                kind: requestedKind,
                page: page,
                topicIds: usesIncrementalRefresh ? incrementalTopicIDs : [],
                order: nil,
                ascending: nil,
                categorySlug: categorySlug,
                categoryId: categoryId,
                parentCategorySlug: parentSlug,
                tag: primaryTag,
                additionalTags: additionalTags,
                matchAllTags: !additionalTags.isEmpty
            )
            let recoveryURL = appViewModel.cloudflareRecoveryTopicListURL(query: topicListQuery)
            let fetch: () async throws -> TopicListState = {
                try await sessionStore.fetchTopicList(
                    query: topicListQuery
                )
            }
            let operationDescription = (page == nil && reset)
                ? "刷新首页话题列表"
                : "加载更多首页话题"
            let fetchWithRecovery: () async throws -> TopicListState = {
                try await self.appViewModel.performWithCloudflareRecovery(
                    operation: operationDescription,
                    originURL: recoveryURL,
                    work: fetch
                )
            }

            let response: TopicListState
            if reset && page == nil && requestedKind == .latest {
                response = try await FireAPMManager.shared.withSpan(
                    .feedLatestInitialLoad,
                    metadata: [
                        "category_id": categoryId.map(String.init) ?? "none",
                        "tag": primaryTag ?? "none",
                        "incremental": usesIncrementalRefresh ? "true" : "false"
                    ],
                    operation: fetchWithRecovery
                )
            } else {
                response = try await fetchWithRecovery()
            }

            guard requestedScope == currentTopicListRefreshScope else {
                return false
            }

            let mergeResult = mergeTopicRows(
                incoming: response.rows,
                reset: reset,
                usesIncrementalRefresh: usesIncrementalRefresh
            )
            applyTopicRows(mergeResult)
            renderedTopicListScope = requestedScope
            topicLoadErrorMessage = nil
            isOffline = response.isCached

            if !usesIncrementalRefresh {
                moreTopicsUrl = response.moreTopicsUrl
                nextTopicsPage = response.nextPage
            }

            appViewModel.pruneTopicDetailState(retainingVisibleTopicIDs: visibleTopicIDs)

            if reset && page == nil {
                topicListMessageBusRefreshController.markRefreshCompleted(
                    for: requestedScope,
                    at: topicListRefreshClock.now
                )
                Task { [appViewModel] in
                    await appViewModel.ensureMessageBusActiveIfPossible()
                }
            }
            return true
        } catch {
            let recoveryOperationDescription = (page == nil && reset)
                ? "刷新首页话题列表"
                : "加载更多首页话题"
            if await appViewModel.attemptReadPathLoginRecovery(
                operation: recoveryOperationDescription,
                error: error
            ) {
                // Tear down the in-flight gate before recursing; without this
                // the inner `loadTopics` returns immediately on the
                // `isLoadingTopics` guard, and the `reset && !force && !rows.isEmpty`
                // guard would also short-circuit incremental refreshes.
                isLoadingTopics = false
                isAppendingTopics = false
                return await loadTopics(
                    page: page,
                    reset: reset,
                    force: true,
                    refreshMode: refreshMode
                )
            }
            if !force,
               case FireUniFfiError.StaleSessionResponse = error {
                isLoadingTopics = false
                isAppendingTopics = false
                return await loadTopics(
                    page: page,
                    reset: reset,
                    force: true,
                    refreshMode: refreshMode
                )
            }
            if await appViewModel.handleRecoverableSessionErrorIfNeeded(error) {
                return false
            }
            topicLoadErrorMessage = error.localizedDescription
            return false
        }
    }

    private func cancelPendingTopicListRefresh() {
        pendingTopicListRefreshTask?.cancel()
        pendingTopicListRefreshTask = nil

        let scope = currentTopicListRefreshScope
        topicListMessageBusRefreshController.clearPending(for: scope)
    }

    private func applyTopicRows(_ result: FireHomeTopicRowsMergeResult) {
        topicEntities = result.entities
        topicOrder = result.order
        topicRows = result.rows
        updateTopicRowContentTokens(
            rows: result.rows,
            dirtyTopicIDs: result.dirtyTopicIDs,
            rebuildAll: result.rebuildAllTokens
        )
        visibleTopicIDs = Self.sanitizedVisibleTopicIDs(
            currentTopicIDs: result.rows.map(\.topic.id),
            candidateVisibleTopicIDs: visibleTopicIDs
        )
    }

    private func clearTopicRows() {
        topicEntities.removeAll()
        topicOrder.removeAll()
        topicRowContentTokensByID = [:]
        topicRows = []
        visibleTopicIDs = []
        moreTopicsUrl = nil
        nextTopicsPage = nil
        renderedTopicListScope = nil
    }

    private func mergeTopicRows(
        incoming: [FireTopicRowPresentation],
        reset: Bool,
        usesIncrementalRefresh: Bool
    ) -> FireHomeTopicRowsMergeResult {
        if reset {
            if usesIncrementalRefresh {
                let rows = FireTopicListMessageBusRefreshMerger.merge(
                    existing: topicRows,
                    incoming: incoming
                )
                var entities = FireEntityIndex<UInt64, FireTopicRowPresentation>()
                entities.replaceAll(rows, id: \.topic.id)
                let order = FireOrderedIDList(ids: rows.map(\.topic.id))
                return FireHomeTopicRowsMergeResult(
                    rows: rows,
                    entities: entities,
                    order: order,
                    dirtyTopicIDs: Set(incoming.map(\.topic.id)),
                    rebuildAllTokens: false
                )
            }
            var entities = FireEntityIndex<UInt64, FireTopicRowPresentation>()
            entities.replaceAll(incoming, id: \.topic.id)
            let order = FireOrderedIDList(ids: incoming.map(\.topic.id))
            return FireHomeTopicRowsMergeResult(
                rows: incoming,
                entities: entities,
                order: order,
                dirtyTopicIDs: Set(incoming.map(\.topic.id)),
                rebuildAllTokens: true
            )
        }

        var entities = topicEntities
        entities.upsert(incoming, id: \.topic.id)
        var order = topicOrder
        order.append(incoming.map(\.topic.id))
        return FireHomeTopicRowsMergeResult(
            rows: entities.orderedValues(for: order),
            entities: entities,
            order: order,
            dirtyTopicIDs: Set(incoming.map(\.topic.id)),
            rebuildAllTokens: false
        )
    }

    private func updateTopicRowContentTokens(
        rows: [FireTopicRowPresentation],
        dirtyTopicIDs: Set<UInt64>,
        rebuildAll: Bool
    ) {
        let currentTopicIDs = Set(rows.map(\.topic.id))
        var nextTokens: [UInt64: String]
        if rebuildAll {
            nextTokens = [:]
            nextTokens.reserveCapacity(rows.count)
        } else {
            nextTokens = topicRowContentTokensByID.filter { currentTopicIDs.contains($0.key) }
        }

        for row in rows where rebuildAll || dirtyTopicIDs.contains(row.topic.id) {
            nextTokens[row.topic.id] = makeTopicRowContentToken(row)
        }
        topicRowContentTokensByID = nextTokens
    }

    private func makeTopicRowContentToken(_ row: FireTopicRowPresentation) -> String {
        let topic = row.topic
        let category = categoryPresentation(for: topic.categoryId)
        var parts: [String] = []
        parts.reserveCapacity(26)
        parts.append(String(topic.id))
        parts.append(topic.title)
        parts.append(topic.slug)
        parts.append(String(topic.postsCount))
        parts.append(String(topic.replyCount))
        parts.append(String(topic.views))
        parts.append(String(topic.likeCount))
        parts.append(topic.excerpt ?? "")
        parts.append(topic.createdAt ?? "")
        parts.append(topic.lastPostedAt ?? "")
        parts.append(topic.lastPosterUsername ?? "")
        parts.append(topic.categoryId.map(String.init) ?? "")
        parts.append(String(topic.pinned))
        parts.append(String(topic.closed))
        parts.append(String(topic.archived))
        parts.append(String(topic.unseen))
        parts.append(String(row.hasUnreadPosts))
        parts.append(String(topic.unreadPosts))
        parts.append(String(topic.newPosts))
        parts.append(topic.lastReadPostNumber.map(String.init) ?? "")
        parts.append(String(topic.highestPostNumber))
        parts.append(row.excerptText ?? "")
        parts.append(row.originalPosterUsername ?? "")
        parts.append(row.originalPosterAvatarTemplate ?? "")
        parts.append(row.tagNames.joined(separator: ","))
        parts.append(row.statusLabels.joined(separator: ","))
        parts.append(category.map { "\($0.id)|\($0.displayName)|\($0.colorHex ?? "")" } ?? "")
        return parts.joined(separator: "\u{1F}")
    }
}
