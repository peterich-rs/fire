import Foundation
import WebKit

private enum FireLoginPreparationError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Unable to prepare login network access."
        }
    }
}

private enum FireDiagnosticsAccessError: LocalizedError {
    case unavailable
    case traceNotFound

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Diagnostics are unavailable because the shared session store was not initialized."
        case .traceNotFound:
            "The selected network request trace is no longer available."
        }
    }
}

@MainActor
final class FireAppViewModel: ObservableObject {
    @Published private(set) var session: SessionState = .placeholder()
    @Published private(set) var selectedTopicKind: TopicListKindState = .latest
    @Published private(set) var topics: [TopicSummaryState] = []
    @Published private(set) var topicRows: [FireTopicRowPresentation] = []
    @Published private(set) var moreTopicsUrl: String?
    @Published private(set) var nextTopicsPage: UInt32?
    @Published private(set) var topicCategories: [UInt64: FireTopicCategoryPresentation] = [:]
    @Published private(set) var topicDetails: [UInt64: TopicDetailState] = [:]
    @Published private(set) var isLoadingTopics = false
    @Published private(set) var isAppendingTopics = false
    @Published private(set) var loadingTopicIDs: Set<UInt64> = []
    @Published var errorMessage: String?
    @Published var isPresentingLogin = false
    @Published var isPreparingLogin = false

    private var sessionStore: FireSessionStore?
    private var loginCoordinator: FireWebViewLoginCoordinator?
    private var sessionStoreInitializationTask: Task<FireSessionStore, Error>?
    private let loginURL = URL(string: "https://linux.do")!

    init() {}

    func loadInitialState() {
        Task {
            do {
                let loginCoordinator = try await loginCoordinatorValue()
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                if let restored = try await loginCoordinator.restorePersistedSessionIfAvailable() {
                    await applySession(restored)
                } else {
                    await applySession(await sessionStore.snapshot())
                }
                await refreshTopicsIfPossible(force: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshSession() {
        Task {
            do {
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                await applySession(await sessionStore.snapshot())
                await refreshTopicsIfPossible(force: false)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openLogin() {
        guard !isPreparingLogin else {
            return
        }

        errorMessage = nil
        isPreparingLogin = true

        Task {
            defer { isPreparingLogin = false }

            do {
                _ = try await loginCoordinatorValue()
                try await prepareLoginNetworkAccess()
                isPresentingLogin = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func completeLogin(from webView: WKWebView) {
        Task {
            do {
                let loginCoordinator = try await loginCoordinatorValue()
                errorMessage = nil
                await applySession(try await loginCoordinator.completeLogin(from: webView))
                isPresentingLogin = false
                await refreshTopicsIfPossible(force: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshBootstrap() {
        Task {
            do {
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                await applySession(try await sessionStore.refreshBootstrapIfNeeded())
                await refreshTopicsIfPossible(force: false)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func logout() {
        Task {
            do {
                let loginCoordinator = try await loginCoordinatorValue()
                errorMessage = nil
                await applySession(try await loginCoordinator.logout())
                selectedTopicKind = .latest
                clearTopicState()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectTopicKind(_ kind: TopicListKindState) {
        guard selectedTopicKind != kind else {
            return
        }
        selectedTopicKind = kind
        refreshTopics()
    }

    func refreshTopics() {
        Task {
            await refreshTopicsIfPossible(force: true)
        }
    }

    func loadMoreTopics() {
        guard let nextTopicsPage else {
            return
        }

        Task {
            await loadTopics(page: nextTopicsPage, reset: false, force: true)
        }
    }

    func loadTopicDetail(topicId: UInt64, force: Bool = false) {
        guard let sessionStore else {
            return
        }

        if loadingTopicIDs.contains(topicId) {
            return
        }
        if topicDetails[topicId] != nil && !force {
            return
        }
        if !session.readiness.canReadAuthenticatedApi {
            clearTopicState()
            return
        }

        loadingTopicIDs.insert(topicId)

        Task {
            defer { loadingTopicIDs.remove(topicId) }

            do {
                errorMessage = nil
                let detail = try await sessionStore.fetchTopicDetail(
                    query: TopicDetailQueryState(
                        topicId: topicId,
                        postNumber: nil,
                        trackVisit: true,
                        filter: nil,
                        usernameFilters: nil,
                        filterTopLevelReplies: false
                    )
                )
                topicDetails[topicId] = detail
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func topicDetail(for topicId: UInt64) -> TopicDetailState? {
        topicDetails[topicId]
    }

    func isLoadingTopic(topicId: UInt64) -> Bool {
        loadingTopicIDs.contains(topicId)
    }

    func categoryPresentation(for categoryID: UInt64?) -> FireTopicCategoryPresentation? {
        guard let categoryID else {
            return nil
        }
        return topicCategories[categoryID]
    }

    func listLogFiles() async throws -> [LogFileSummaryState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.listLogFiles()
    }

    func readLogFile(relativePath: String) async throws -> LogFileDetailState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.readLogFile(relativePath: relativePath)
    }

    func listNetworkTraces(limit: UInt64 = 200) async throws -> [NetworkTraceSummaryState] {
        let sessionStore = try await sessionStoreValue()
        return await sessionStore.listNetworkTraces(limit: limit)
    }

    func networkTraceDetail(traceID: UInt64) async throws -> NetworkTraceDetailState {
        let sessionStore = try await sessionStoreValue()
        guard let detail = await sessionStore.networkTraceDetail(traceID: traceID) else {
            throw FireDiagnosticsAccessError.traceNotFound
        }
        return detail
    }

    private func prepareLoginNetworkAccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true

        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: loginURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await session.data(for: request)
        guard response is HTTPURLResponse else {
            throw FireLoginPreparationError.invalidResponse
        }
    }

    private func refreshTopicsIfPossible(force: Bool) async {
        await loadTopics(page: nil, reset: true, force: force)
    }

    private func loadTopics(page: UInt32?, reset: Bool, force: Bool) async {
        if !session.readiness.canReadAuthenticatedApi {
            clearTopicState()
            return
        }
        if isLoadingTopics {
            return
        }
        if reset && !force && !topics.isEmpty {
            return
        }

        isLoadingTopics = true
        isAppendingTopics = !reset
        defer {
            isLoadingTopics = false
            isAppendingTopics = false
        }

        do {
            let sessionStore = try await sessionStoreValue()
            errorMessage = nil
            let requestedKind = selectedTopicKind
            let response = try await sessionStore.fetchTopicList(
                query: TopicListQueryState(
                    kind: requestedKind,
                    page: page,
                    topicIds: [],
                    order: nil,
                    ascending: nil
                )
            )
            let mergedTopics = reset ? response.topics : mergeTopics(existing: topics, incoming: response.topics)
            let visibleTopicIDs = Set(mergedTopics.map(\.id))
            let topicRows = await Task.detached(priority: .userInitiated) {
                FireTopicPresentation.buildRowPresentations(from: mergedTopics)
            }.value
            guard requestedKind == selectedTopicKind else {
                return
            }
            topics = mergedTopics
            self.topicRows = topicRows
            moreTopicsUrl = response.moreTopicsUrl
            nextTopicsPage = FireTopicPresentation.nextPage(from: response.moreTopicsUrl)
            topicDetails = topicDetails.filter { visibleTopicIDs.contains($0.key) }
            loadingTopicIDs = loadingTopicIDs.intersection(visibleTopicIDs)
        } catch {
            if reset {
                topics = []
                topicRows = []
                moreTopicsUrl = nil
                nextTopicsPage = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    private func clearTopicState() {
        topics = []
        topicRows = []
        moreTopicsUrl = nil
        nextTopicsPage = nil
        topicDetails = [:]
        isLoadingTopics = false
        isAppendingTopics = false
        loadingTopicIDs = []
    }

    private func applySession(_ session: SessionState) async {
        self.session = session
        let preloadedJSON = session.bootstrap.preloadedJson
        let categories = await Task.detached(priority: .userInitiated) {
            FireTopicPresentation.parseCategories(from: preloadedJSON)
        }.value
        guard self.session.bootstrap.preloadedJson == preloadedJSON else {
            return
        }
        topicCategories = categories
    }

    private func mergeTopics(
        existing: [TopicSummaryState],
        incoming: [TopicSummaryState]
    ) -> [TopicSummaryState] {
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var orderedIDs = existing.map(\.id)

        for topic in incoming {
            if merged[topic.id] == nil {
                orderedIDs.append(topic.id)
            }
            merged[topic.id] = topic
        }

        return orderedIDs.compactMap { merged[$0] }
    }

    private func sessionStoreValue() async throws -> FireSessionStore {
        if let sessionStore {
            return sessionStore
        }

        if let sessionStoreInitializationTask {
            let sessionStore = try await sessionStoreInitializationTask.value
            self.sessionStore = sessionStore
            return sessionStore
        }

        let initializationTask = Task.detached(priority: .userInitiated) {
            try FireSessionStore()
        }
        sessionStoreInitializationTask = initializationTask

        do {
            let sessionStore = try await initializationTask.value
            sessionStoreInitializationTask = nil
            self.sessionStore = sessionStore
            return sessionStore
        } catch {
            sessionStoreInitializationTask = nil
            throw error
        }
    }

    private func loginCoordinatorValue() async throws -> FireWebViewLoginCoordinator {
        if let loginCoordinator {
            return loginCoordinator
        }

        let sessionStore = try await sessionStoreValue()
        let loginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
        self.loginCoordinator = loginCoordinator
        return loginCoordinator
    }
}
