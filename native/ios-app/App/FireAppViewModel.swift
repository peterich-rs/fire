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
    @Published var selectedTopicKind: TopicListKindState = .latest
    @Published private(set) var topics: [TopicSummaryState] = []
    @Published private(set) var moreTopicsUrl: String?
    @Published private(set) var topicDetails: [UInt64: TopicDetailState] = [:]
    @Published private(set) var isLoadingTopics = false
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
                    session = restored
                } else {
                    session = await sessionStore.snapshot()
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
            session = await sessionStore.snapshot()
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
                session = try await loginCoordinator.completeLogin(from: webView)
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
                session = try await sessionStore.refreshBootstrapIfNeeded()
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
                session = try await loginCoordinator.logout()
                selectedTopicKind = .latest
                clearTopicState()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshTopics() {
        Task {
            await refreshTopicsIfPossible(force: true)
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
        guard let sessionStore else {
            return
        }

        if !session.readiness.canReadAuthenticatedApi {
            clearTopicState()
            return
        }
        if !force && !topics.isEmpty {
            return
        }

        isLoadingTopics = true
        defer { isLoadingTopics = false }

        do {
            errorMessage = nil
            let requestedKind = selectedTopicKind
            let response = try await sessionStore.fetchTopicList(
                query: TopicListQueryState(
                    kind: requestedKind,
                    page: nil,
                    topicIds: [],
                    order: nil,
                    ascending: nil
                )
            )
            guard requestedKind == selectedTopicKind else {
                return
            }
            topics = response.topics
            moreTopicsUrl = response.moreTopicsUrl
            let visibleTopicIDs = Set(response.topics.map(\.id))
            topicDetails = topicDetails.filter { visibleTopicIDs.contains($0.key) }
            loadingTopicIDs = loadingTopicIDs.intersection(visibleTopicIDs)
        } catch {
            topics = []
            moreTopicsUrl = nil
            errorMessage = error.localizedDescription
        }
    }

    private func clearTopicState() {
        topics = []
        moreTopicsUrl = nil
        topicDetails = [:]
        isLoadingTopics = false
        loadingTopicIDs = []
    }
}
