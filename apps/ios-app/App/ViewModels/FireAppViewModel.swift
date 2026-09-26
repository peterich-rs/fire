import Foundation
import UIKit
import WebKit

@MainActor
final class FireAppViewModel: ObservableObject {
    typealias LoginCoordinatorPreloader = @Sendable () async throws -> Void
    typealias LoginNetworkWarmup = @Sendable () async -> Void

    static let messageBusErrorPrefix = "实时同步连接失败："
    static let loginRequiredMessage = "登录状态已失效，请重新登录。"
    static let authDiagnosticsLogTarget = "ios.auth"
    static let topicRouteLogTarget = "ios.topic-route"
    static let topicDetailLogTarget = "ios.topic-detail"
    static let diagnosticsLifecycleLogTarget = "ios.lifecycle"

    // MARK: - Session

    @Published var session: SessionState = .placeholder()

    // MARK: - General UI state

    @Published var errorMessage: String?
    @Published var isBootstrappingSession = false
    @Published var isStartupLoadingVisible = false
    @Published var authPresentationState: FireAuthPresentationState?
    @Published var isPreparingLogin = false
    @Published var isSyncingLoginSession = false
    @Published var canSyncLoginSession = false
    @Published var savedLoginCredential: FireSavedCredential?
    @Published var lastLoginMethod: FireLastLoginMethod?
    @Published var isLoggingOut = false
    @Published var isStartupValidationComplete = false
    /// Non-nil while mid-session Google/headless reauth is running on the main shell.
    @Published var midSessionReauthMessage: String?
    @Published var isMidSessionReauthInFlight = false
    var isStartupValidationInFlight = false
    /// Set when the user taps logout so deauth routes to the credential form only.
    var didRequestExplicitLogout = false
    /// Set when MessageBus `/logout/{user_id}` revokes the session.
    var serverForcedLogout = false
    /// Cookies can restore a login shell before home HTML hydrates `current_username`.
    var isHydratingBootstrap = false
    var lastBootstrapHydrationAttemptKey: String?

    // MARK: - Private

    var sessionStore: FireSessionStore?
    var loginCoordinator: FireWebViewLoginCoordinator?
    var cloudflareChallengeHandler: FireCloudflareChallengeRuntimeHandler?
    var clearanceResolvedHandler: FireClearanceResolvedRuntimeHandler?
    var cookieSelfHealingHandler: FireCookieSelfHealingRuntimeHandler?
    var sessionCandidateHandler: FireSessionCandidateRuntimeHandler?
    var userApiKeyCryptoHandler: FireUserApiKeyCryptoRuntimeHandler?
    var sessionStoreInitializationTask: Task<FireSessionStore, Error>?
    var initialStateTask: Task<Void, Never>?
    var initialStateLoadingDelayTask: Task<Void, Never>?
    var initialStateLoadGeneration: UInt64 = 0
    var loginSyncReadinessTask: Task<Void, Never>?
    var cachedLoginSyncReadiness: CachedLoginSyncReadiness?
    /// Single-flight read-path login recovery: at most one resync runs per session
    /// epoch, and once an epoch's resync has failed we stop retrying it on read
    /// errors so the caller falls back to reporting the original error.
    var readPathLoginRecoveryTask: Task<Bool, Never>?
    var lastReadPathLoginGeneration: UInt64 = 0
    var hasLatchedAskEnableBrowserTransport = false
    var readPathLoginRecoveryEpoch: UInt64?
    var readPathLoginRecoveryAttemptedEpochs: Set<UInt64> = []
    /// Single-flight mid-session headless reauth (Google first).
    var midSessionReauthTask: Task<Bool, Never>?
    var midSessionReauthEngine: FireHeadlessExternalLoginEngine?
    var midSessionReauthContinuation: CheckedContinuation<Bool, Never>?
    let loginURL = URL(string: "https://linux.do/")!
    let loginCoordinatorPreloader: LoginCoordinatorPreloader?
    let loginNetworkWarmup: LoginNetworkWarmup?
    private lazy var appServiceHost = FireAppServiceHost(owner: self)
    lazy var topicInteraction = FireTopicInteractionService(host: appServiceHost)
    lazy var notificationService = FireNotificationService(host: appServiceHost)
    lazy var searchService = FireSearchService(host: appServiceHost)
    lazy var composerSession = FireComposerSession(appViewModel: self)
    // MessageBus
    var messageBusCoordinator: FireMessageBusCoordinator?
    var isMessageBusActive = false
    var messageBusStartRetryCount = 0
    var messageBusRetryTask: Task<Void, Never>?
    var topLevelAPMRoute = "session.onboarding"
    weak var homeFeedStore: FireHomeFeedStore?
    weak var notificationStore: FireNotificationStore?
    weak var topicDetailStore: FireTopicDetailStore?
    weak var chatChannelsStore: FireChatChannelsStore?
    lazy var appStateRefreshCoordinator = FireAppStateRefreshCoordinator { [weak self] event in
        self?.handleAppStateRefreshEvent(event)
    }
    lazy var stateObserverCoordinator = FireStateObserverCoordinator(
        onSession: { [weak self] snapshot in
            guard let self else { return }
            await self.applySession(snapshot, activateMessageBus: false)
        },
        onTopicList: { [weak self] snapshot in
            self?.homeFeedStore?.applyTopicList(snapshot)
        },
        onTopicListPatches: { [weak self] batch in
            self?.homeFeedStore?.applyTopicListPatches(batch)
        },
        onNotificationCenter: { [weak self] snapshot in
            self?.notificationStore?.apply(
                centerState: snapshot,
                updateRecent: snapshot.hasLoadedRecent,
                updateFull: snapshot.hasLoadedFull
            )
        }
    )

    init(
        initialSession: SessionState = .placeholder(),
        loginCoordinatorPreloader: LoginCoordinatorPreloader? = nil,
        loginNetworkWarmup: LoginNetworkWarmup? = nil
    ) {
        self.session = initialSession
        self.loginCoordinatorPreloader = loginCoordinatorPreloader
        self.loginNetworkWarmup = loginNetworkWarmup
    }

    func bindHomeFeedStore(_ store: FireHomeFeedStore) {
        homeFeedStore = store
    }

    func bindChatChannelsStore(_ store: FireChatChannelsStore) {
        chatChannelsStore = store
    }

    func bindNotificationStore(_ store: FireNotificationStore) {
        notificationStore = store
    }

    func bindTopicDetailStore(_ store: FireTopicDetailStore) {
        topicDetailStore = store
    }

    func currentSessionStore() -> FireSessionStore? {
        sessionStore
    }

    func sessionStoreValue() async throws -> FireSessionStore {
        if let sessionStore {
            await registerStateObserver(with: sessionStore)
            await configureAuthenticatedWriteHostResyncProvider(with: sessionStore)
            return sessionStore
        }

        if let sessionStoreInitializationTask {
            let sessionStore = try await sessionStoreInitializationTask.value
            self.sessionStore = sessionStore
            await FireAPMManager.shared.attachSessionStore(sessionStore)
            await registerStateObserver(with: sessionStore)
            await configureAuthenticatedWriteHostResyncProvider(with: sessionStore)
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
            await FireAPMManager.shared.attachSessionStore(sessionStore)
            await registerStateObserver(with: sessionStore)
            await configureAuthenticatedWriteHostResyncProvider(with: sessionStore)
            return sessionStore
        } catch {
            sessionStoreInitializationTask = nil
            throw error
        }
    }
}
