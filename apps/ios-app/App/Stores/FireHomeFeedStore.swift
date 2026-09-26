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
    @Published var selectedTopicKind: TopicListKindState = .latest
    @Published var selectedHomeCategoryId: UInt64?
    @Published var selectedHomeTags: [String] = []
    @Published var topicRows: [FireTopicRowPresentation] = []
    @Published var moreTopicsUrl: String?
    @Published var nextTopicsPage: UInt32?
    @Published var allCategories: [FireTopicCategoryPresentation] = []
    @Published var topicCategories: [UInt64: FireTopicCategoryPresentation] = [:]
    @Published var topTags: [String] = []
    @Published var canTagTopics = false
    @Published var isLoadingTopics = false
    @Published var isAppendingTopics = false
    @Published var topicLoadErrorMessage: String?
    @Published var topicLoadErrorIsCloudflare = false
    @Published var isOffline = false

    var visibleTopicIDs: Set<UInt64> = []

    private let feedSession: FireHomeFeedSession

    init(appViewModel: FireAppViewModel) {
        feedSession = FireHomeFeedSession(appViewModel: appViewModel)
        feedSession.attach(store: self)
        feedSession.applySession(appViewModel.session)
    }

    var selectedHomeCategoryPresentation: FireTopicCategoryPresentation? {
        categoryPresentation(for: selectedHomeCategoryId)
    }

    var currentScopeNextTopicsPage: UInt32? {
        feedSession.hasResolvedCurrentScope ? nextTopicsPage : nil
    }

    var topicListDisplayState: FireHomeTopicListDisplayState {
        FireHomeTopicListDisplayState.resolve(
            hasResolvedCurrentScope: feedSession.hasResolvedCurrentScope,
            hasRows: !topicRows.isEmpty,
            errorMessage: topicLoadErrorMessage
        )
    }

    static func sanitizedVisibleTopicIDs(
        currentTopicIDs: [UInt64],
        candidateVisibleTopicIDs: Set<UInt64>
    ) -> Set<UInt64> {
        FireHomeFeedSession.sanitizedVisibleTopicIDs(
            currentTopicIDs: currentTopicIDs,
            candidateVisibleTopicIDs: candidateVisibleTopicIDs
        )
    }

    static func applyHomeRowCountPatch(
        _ row: FireTopicRowPresentation,
        patch: TopicHomeRowCountPatchState
    ) -> FireTopicRowPresentation? {
        FireHomeFeedSession.applyHomeRowCountPatch(row, patch: patch)
    }

    nonisolated static func canScheduleIncrementalMessageBusRefresh(
        scope: FireTopicListRefreshScope,
        renderedScope: FireTopicListRefreshScope?,
        isTopicListVisible: Bool,
        isSceneActive: Bool,
        hasRows: Bool
    ) -> Bool {
        FireHomeFeedSession.canScheduleIncrementalMessageBusRefresh(
            scope: scope,
            renderedScope: renderedScope,
            isTopicListVisible: isTopicListVisible,
            isSceneActive: isSceneActive,
            hasRows: hasRows
        )
    }

    func updateVisibleTopicIDs(_ topicIDs: Set<UInt64>) {
        feedSession.updateVisibleTopicIDs(topicIDs)
    }

    func setTopicListVisible(_ isVisible: Bool) {
        feedSession.setTopicListVisible(isVisible)
    }

    func setSceneActive(_ isActive: Bool) {
        feedSession.setSceneActive(isActive)
    }

    func applySession(_ session: SessionState) {
        feedSession.applySession(session)
    }

    func categoryPresentation(for categoryID: UInt64?) -> FireTopicCategoryPresentation? {
        feedSession.categoryPresentation(for: categoryID)
    }

    func topicRow(for topicID: UInt64) -> FireTopicRowPresentation? {
        feedSession.topicRow(for: topicID)
    }

    func topicRowContentToken(for topicID: UInt64) -> String? {
        feedSession.topicRowContentToken(for: topicID)
    }

    @discardableResult
    func applyHomeRowCountPatch(_ patch: TopicHomeRowCountPatchState) -> Bool {
        feedSession.applyHomeRowCountPatch(patch)
    }

    func selectTopicKind(_ kind: TopicListKindState) {
        feedSession.selectTopicKind(kind)
    }

    func selectHomeCategory(_ categoryID: UInt64?) {
        feedSession.selectHomeCategory(categoryID)
    }

    func addHomeTag(_ tag: String) {
        feedSession.addHomeTag(tag)
    }

    func removeHomeTag(_ tag: String) {
        feedSession.removeHomeTag(tag)
    }

    func clearHomeTags() {
        feedSession.clearHomeTags()
    }

    func refreshTopics() {
        feedSession.refreshTopics()
    }

    func refreshTopicsAsync() async {
        await feedSession.refreshTopicsAsync()
    }

    func applyTopicList(_ state: TopicListState) {
        feedSession.applyTopicList(state)
    }

    func applyTopicListPatches(_ batch: TopicListRowPatchBatchState) {
        feedSession.applyTopicListPatches(batch)
    }

    @discardableResult
    func refreshTopicsIfPossible(force: Bool) async -> Bool {
        await feedSession.refreshTopicsIfPossible(force: force)
    }

    func loadMoreTopics() {
        feedSession.loadMoreTopics()
    }

    func handleTopicListMessageBusEvent(_ event: MessageBusEventState) {
        feedSession.handleTopicListMessageBusEvent(event)
    }

    func handleMessageBusStopped() {
        feedSession.handleMessageBusStopped()
    }

    func reset(resetTopicKind: Bool = true) {
        feedSession.reset(resetTopicKind: resetTopicKind)
    }

    func clearTopicLoadError() {
        feedSession.clearTopicLoadError()
    }
}
