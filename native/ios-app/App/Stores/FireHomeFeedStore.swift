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

    private(set) var visibleTopicIDs: Set<UInt64> = []
    private(set) var renderedTopicListScope: FireTopicListRefreshScope?
    private let appViewModel: FireAppViewModel
    private let topicListRefreshClock = ContinuousClock()
    private var pendingTopicListRefreshTask: Task<Void, Never>?
    private var filterChangeRefreshTask: Task<Void, Never>?
    private var topicListMessageBusRefreshController = FireTopicListMessageBusRefreshController()
    private var topicEntities = FireEntityIndex<UInt64, FireTopicRowPresentation>()
    private var topicOrder = FireOrderedIDList<UInt64>()

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

    func updateVisibleTopicIDs(_ topicIDs: Set<UInt64>) {
        visibleTopicIDs = Self.sanitizedVisibleTopicIDs(
            currentTopicIDs: topicRows.map(\.topic.id),
            candidateVisibleTopicIDs: topicIDs
        )
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

    func selectTopicKind(_ kind: TopicListKindState) {
        guard selectedTopicKind != kind else {
            return
        }
        selectedTopicKind = kind
        topicLoadErrorMessage = nil
        scheduleDebouncedRefresh()
    }

    func selectHomeCategory(_ categoryId: UInt64?) {
        guard selectedHomeCategoryId != categoryId else { return }
        selectedHomeCategoryId = categoryId
        selectedHomeTags = []
        topicLoadErrorMessage = nil
        scheduleDebouncedRefresh()
    }

    func addHomeTag(_ tag: String) {
        guard !selectedHomeTags.contains(tag) else { return }
        selectedHomeTags.append(tag)
        topicLoadErrorMessage = nil
        scheduleDebouncedRefresh()
    }

    func removeHomeTag(_ tag: String) {
        guard selectedHomeTags.contains(tag) else { return }
        selectedHomeTags.removeAll { $0 == tag }
        topicLoadErrorMessage = nil
        scheduleDebouncedRefresh()
    }

    func clearHomeTags() {
        guard !selectedHomeTags.isEmpty else { return }
        selectedHomeTags = []
        topicLoadErrorMessage = nil
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

    func refreshTopicsIfPossible(force: Bool) async {
        cancelPendingTopicListRefresh()
        await loadTopics(page: nil, reset: true, force: force, refreshMode: .full)
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

        let allowIncremental = scope.supportsIncrementalMessageBusRefresh
            && renderedTopicListScope == scope
            && !topicRows.isEmpty
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
        topicRows = []
        moreTopicsUrl = nil
        nextTopicsPage = nil
        isLoadingTopics = false
        isAppendingTopics = false
        topicLoadErrorMessage = nil
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

    private var hasResolvedCurrentScope: Bool {
        renderedTopicListScope == currentTopicListRefreshScope
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
        await loadTopics(page: nil, reset: true, force: true, refreshMode: refreshMode)
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
        defer {
            isLoadingTopics = false
            isAppendingTopics = false
        }

        do {
            let sessionStore = try await appViewModel.sessionStoreValue()
            let requestedKind = selectedTopicKind
            let categoryId = selectedHomeCategoryId
            let requestedTags = selectedHomeTags
            let requestedScope = FireTopicListRefreshScope(
                kind: requestedKind,
                categoryId: categoryId,
                tags: requestedTags
            )
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
            let fetch: () async throws -> TopicListState = {
                try await sessionStore.fetchTopicList(
                    query: TopicListQueryState(
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
                )
            }
            let operationDescription = (page == nil && reset)
                ? "刷新首页话题列表"
                : "加载更多首页话题"
            let fetchWithRecovery: () async throws -> TopicListState = {
                try await self.appViewModel.performWithCloudflareRecovery(
                    operation: operationDescription,
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

            let mergedTopicRows = mergeTopicRows(
                incoming: response.rows,
                reset: reset,
                usesIncrementalRefresh: usesIncrementalRefresh
            )
            setTopicRows(mergedTopicRows)
            renderedTopicListScope = requestedScope
            topicLoadErrorMessage = nil

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
            }
            return true
        } catch {
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

    private func setTopicRows(_ rows: [FireTopicRowPresentation]) {
        topicEntities.replaceAll(rows, id: \.topic.id)
        topicOrder.replace(with: rows.map(\.topic.id))
        topicRows = rows
        visibleTopicIDs = Self.sanitizedVisibleTopicIDs(
            currentTopicIDs: rows.map(\.topic.id),
            candidateVisibleTopicIDs: visibleTopicIDs
        )
    }

    private func clearTopicRows() {
        topicEntities.removeAll()
        topicOrder.removeAll()
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
    ) -> [FireTopicRowPresentation] {
        if reset {
            if usesIncrementalRefresh {
                return FireTopicListMessageBusRefreshMerger.merge(
                    existing: topicRows,
                    incoming: incoming
                )
            }
            return incoming
        }

        topicEntities.upsert(incoming, id: \.topic.id)
        topicOrder.append(incoming.map(\.topic.id))
        return topicEntities.orderedValues(for: topicOrder)
    }
}
