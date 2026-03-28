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

@MainActor
final class FireAppViewModel: ObservableObject {
    @Published private(set) var session: SessionState = .placeholder()
    @Published private(set) var selectedTopicKind: TopicListKindState = .latest
    @Published private(set) var topics: [TopicSummaryState] = []
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

    private let sessionStore: FireSessionStore?
    private let loginCoordinator: FireWebViewLoginCoordinator?
    private let loginURL = URL(string: "https://linux.do")!

    init() {
        do {
            let sessionStore = try FireSessionStore()
            self.sessionStore = sessionStore
            self.loginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
        } catch {
            self.sessionStore = nil
            self.loginCoordinator = nil
            self.errorMessage = error.localizedDescription
        }
    }

    func loadInitialState() {
        guard let loginCoordinator, let sessionStore else {
            return
        }

        Task {
            do {
                errorMessage = nil
                if let restored = try await loginCoordinator.restorePersistedSessionIfAvailable() {
                    applySession(restored)
                } else {
                    applySession(await sessionStore.snapshot())
                }
                await refreshTopicsIfPossible(force: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshSession() {
        guard let sessionStore else {
            return
        }

        Task {
            errorMessage = nil
            applySession(await sessionStore.snapshot())
            await refreshTopicsIfPossible(force: false)
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
                try await prepareLoginNetworkAccess()
                isPresentingLogin = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func completeLogin(from webView: WKWebView) {
        guard let loginCoordinator else {
            return
        }

        Task {
            do {
                errorMessage = nil
                applySession(try await loginCoordinator.completeLogin(from: webView))
                isPresentingLogin = false
                await refreshTopicsIfPossible(force: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshBootstrap() {
        guard let sessionStore else {
            return
        }

        Task {
            do {
                errorMessage = nil
                applySession(try await sessionStore.refreshBootstrapIfNeeded())
                await refreshTopicsIfPossible(force: false)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func logout() {
        guard let loginCoordinator else {
            return
        }

        Task {
            do {
                errorMessage = nil
                applySession(try await loginCoordinator.logout())
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
        guard let sessionStore else {
            return
        }
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
            guard requestedKind == selectedTopicKind else {
                return
            }
            topics = reset ? response.topics : mergeTopics(existing: topics, incoming: response.topics)
            moreTopicsUrl = response.moreTopicsUrl
            nextTopicsPage = FireTopicPresentation.nextPage(from: response.moreTopicsUrl)
            let visibleTopicIDs = Set(topics.map(\.id))
            topicDetails = topicDetails.filter { visibleTopicIDs.contains($0.key) }
            loadingTopicIDs = loadingTopicIDs.intersection(visibleTopicIDs)
        } catch {
            if reset {
                topics = []
                moreTopicsUrl = nil
                nextTopicsPage = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    private func clearTopicState() {
        topics = []
        moreTopicsUrl = nil
        nextTopicsPage = nil
        topicDetails = [:]
        isLoadingTopics = false
        isAppendingTopics = false
        loadingTopicIDs = []
    }

    private func applySession(_ session: SessionState) {
        self.session = session
        topicCategories = FireTopicPresentation.parseCategories(from: session.bootstrap.preloadedJson)
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
}
