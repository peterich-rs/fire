import Foundation
import UIKit
import WebKit

@MainActor
final class FireAppViewModel: ObservableObject {
    typealias LoginCoordinatorPreloader = @Sendable () async throws -> Void
    typealias LoginNetworkWarmup = @Sendable () async -> Void

    private static let messageBusErrorPrefix = "实时同步连接失败："
    private static let loginRequiredMessage = "登录状态已失效，请重新登录。"
    private static let authDiagnosticsLogTarget = "ios.auth"
    private static let topicRouteLogTarget = "ios.topic-route"
    private static let topicDetailLogTarget = "ios.topic-detail"
    static let diagnosticsLifecycleLogTarget = "ios.lifecycle"

    // MARK: - Session

    @Published private(set) var session: SessionState = .placeholder()

    // MARK: - General UI state

    @Published var errorMessage: String?
    @Published private(set) var isBootstrappingSession = false
    @Published private(set) var isStartupLoadingVisible = false
    @Published var authPresentationState: FireAuthPresentationState?
    @Published var isPreparingLogin = false
    @Published var isSyncingLoginSession = false
    @Published private(set) var canSyncLoginSession = false
    @Published private(set) var savedLoginCredential: FireSavedCredential?
    @Published private(set) var lastLoginMethod: FireLastLoginMethod?
    @Published var isLoggingOut = false
    @Published private(set) var isStartupValidationComplete = false
    /// Non-nil while mid-session Google/headless reauth is running on the main shell.
    @Published private(set) var midSessionReauthMessage: String?
    @Published private(set) var isMidSessionReauthInFlight = false
    private var isStartupValidationInFlight = false
    /// Set when the user taps logout so deauth routes to the credential form only.
    private var didRequestExplicitLogout = false

    // MARK: - Private

    private var sessionStore: FireSessionStore?
    private var loginCoordinator: FireWebViewLoginCoordinator?
    private var cloudflareChallengeHandler: FireCloudflareChallengeRuntimeHandler?
    private var clearanceResolvedHandler: FireClearanceResolvedRuntimeHandler?
    private var cookieSelfHealingHandler: FireCookieSelfHealingRuntimeHandler?
    private var sessionStoreInitializationTask: Task<FireSessionStore, Error>?
    private var initialStateTask: Task<Void, Never>?
    private var initialStateLoadingDelayTask: Task<Void, Never>?
    private var initialStateLoadGeneration: UInt64 = 0
    private var loginSyncReadinessTask: Task<Void, Never>?
    private var cachedLoginSyncReadiness: CachedLoginSyncReadiness?
    /// Single-flight read-path login recovery: at most one resync runs per session
    /// epoch, and once an epoch's resync has failed we stop retrying it on read
    /// errors so the caller falls back to reporting the original error.
    private var readPathLoginRecoveryTask: Task<Bool, Never>?
    private var readPathLoginRecoveryEpoch: UInt64?
    private var readPathLoginRecoveryAttemptedEpochs: Set<UInt64> = []
    /// Single-flight mid-session headless reauth (Google first).
    private var midSessionReauthTask: Task<Bool, Never>?
    private var midSessionReauthEngine: FireHeadlessExternalLoginEngine?
    private var midSessionReauthContinuation: CheckedContinuation<Bool, Never>?
    private let loginURL = URL(string: "https://linux.do/")!
    private let loginCoordinatorPreloader: LoginCoordinatorPreloader?
    private let loginNetworkWarmup: LoginNetworkWarmup?
    private lazy var appServiceHost = FireAppServiceHost(owner: self)
    lazy var topicInteraction = FireTopicInteractionService(host: appServiceHost)
    lazy var notificationService = FireNotificationService(host: appServiceHost)
    lazy var searchService = FireSearchService(host: appServiceHost)
    // MessageBus
    private var messageBusCoordinator: FireMessageBusCoordinator?
    private var isMessageBusActive = false
    private var messageBusStartRetryCount = 0
    private var messageBusRetryTask: Task<Void, Never>?
    private var topLevelAPMRoute = "session.onboarding"
    private weak var homeFeedStore: FireHomeFeedStore?
    private weak var notificationStore: FireNotificationStore?
    private weak var topicDetailStore: FireTopicDetailStore?
    private lazy var appStateRefreshCoordinator = FireAppStateRefreshCoordinator { [weak self] event in
        self?.handleAppStateRefreshEvent(event)
    }
    private lazy var stateObserverCoordinator = FireStateObserverCoordinator(
        onSession: { [weak self] snapshot in
            guard let self else { return }
            await self.applySession(snapshot, activateMessageBus: false)
        },
        onTopicList: { [weak self] snapshot in
            self?.homeFeedStore?.applyTopicList(snapshot)
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

    var isPresentingLogin: Bool {
        authPresentationState != nil
    }

    func bindHomeFeedStore(_ store: FireHomeFeedStore) {
        homeFeedStore = store
    }

    func bindNotificationStore(_ store: FireNotificationStore) {
        notificationStore = store
    }

    func bindTopicDetailStore(_ store: FireTopicDetailStore) {
        topicDetailStore = store
    }

    func updateWidgetData() {
        guard session.readiness.canReadAuthenticatedApi else {
            FireWidgetSnapshotWriter.clear()
            return
        }
        FireWidgetSnapshotWriter.update(
            session: session,
            topicRows: homeFeedStore?.topicRows ?? [],
            unreadNotificationCount: notificationStore?.unreadCount ?? 0
        )
    }

    // MARK: - Lifecycle

    func loadInitialState() {
        initialStateLoadGeneration &+= 1
        let generation = initialStateLoadGeneration

        initialStateTask?.cancel()
        initialStateLoadingDelayTask?.cancel()
        FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
        isBootstrappingSession = true
        isStartupLoadingVisible = false

        initialStateLoadingDelayTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            guard let self else { return }
            guard self.initialStateLoadGeneration == generation else { return }
            guard self.isBootstrappingSession else { return }
            self.isStartupLoadingVisible = true
        }

        initialStateTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.finishInitialStateLoading(generation: generation)
            }

            do {
                try await FireAPMManager.shared.withSpan(.appLaunchRestoreSession) {
                    let sessionStore = try await self.sessionStoreValue()
                    guard self.initialStateLoadGeneration == generation else { return }
                    self.errorMessage = nil
                    _ = try await sessionStore.prepareStartupSession()
                    guard self.initialStateLoadGeneration == generation else { return }
                    Task {
                        try? await sessionStore.ensurePreloadedDataLoaded()
                    }
                }
            } catch {
                guard self.initialStateLoadGeneration == generation else { return }
                if await self.handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func completeStartupAfterPreheat() async {
        let generation = initialStateLoadGeneration
        do {
            let sessionStore = try await sessionStoreValue()
            guard self.initialStateLoadGeneration == generation else { return }
            self.errorMessage = nil
            let loginState = try await sessionStore.determineLoginStateWithProbe()
            guard self.initialStateLoadGeneration == generation else { return }
            switch loginState {
            case .loggedIn:
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(true)
                try await sessionStore.triggerAppStateRefresh(
                    .sessionRestored,
                    handler: appStateRefreshCoordinator
                )
                let snapshot = try await sessionStore.snapshot()
                guard self.initialStateLoadGeneration == generation else { return }
                await self.ensureLastLoginMethodLoaded(using: sessionStore)
                await self.applySession(snapshot, activateMessageBus: false)
            case .networkErrorPreserveState, .sessionExpired, .notLoggedIn:
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
                let snapshot = try await sessionStore.snapshot()
                guard self.initialStateLoadGeneration == generation else { return }
                await self.applySession(snapshot, activateMessageBus: false)
            @unknown default:
                break
            }
        } catch {
            guard self.initialStateLoadGeneration == generation else { return }
            if await self.handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            if let sessionStore = self.sessionStore,
               let snapshot = try? await sessionStore.snapshot() {
                await self.applySession(snapshot, activateMessageBus: false)
            }
            self.errorMessage = error.localizedDescription
        }
    }

    func completeStartupAfterPreheatFailure(message: String?) {
        initialStateLoadGeneration &+= 1
        initialStateTask?.cancel()
        initialStateTask = nil
        initialStateLoadingDelayTask?.cancel()
        initialStateLoadingDelayTask = nil
        isBootstrappingSession = false
        isStartupLoadingVisible = false
        FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
        if let message, !message.isEmpty {
            errorMessage = message
        }
    }

    func performStartupValidation() async {
        guard !isStartupValidationComplete else { return }
        guard !isStartupValidationInFlight else { return }
        isStartupValidationInFlight = true
        defer {
            isStartupValidationInFlight = false
            isStartupValidationComplete = true
        }

        do {
            let sessionStore = try await sessionStoreValue()
            _ = try await sessionStore.prepareStartupSession()
            do {
                _ = try await sessionStore.awaitPreloadedData()
            } catch {
                let snapshot = try? await sessionStore.snapshot()
                let readiness = snapshot?.readiness
                guard readiness?.canReadAuthenticatedApi == true
                    || readiness?.hasLoginCookie == true
                else {
                    throw error
                }
            }
            await completeStartupAfterPreheat()
        } catch {
            completeStartupAfterPreheatFailure(message: "网络异常，请重新登录")
        }
    }

    func prepareLoginForm() async {
        do {
            let sessionStore = try await sessionStoreValue()
            savedLoginCredential = try await sessionStore.loadSavedCredential()
            lastLoginMethod = try await sessionStore.loadLastLoginMethod()
            _ = try await loginCoordinatorValue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureLastLoginMethodLoaded(using sessionStore: FireSessionStore) async {
        guard lastLoginMethod == nil else { return }
        lastLoginMethod = try? await sessionStore.loadLastLoginMethod()
    }

    func openLogin() {
        guard authPresentationState == nil else { return }
        errorMessage = nil
        canSyncLoginSession = false
        cachedLoginSyncReadiness = nil
        setAuthPresentationState(.login)

        Task { await prepareLoginForm() }
    }

    func completeLogin(
        from webView: WKWebView,
        method: FireLastLoginMethod? = nil
    ) {
        Task {
            _ = await completeLoginAwaitingResult(from: webView, method: method)
        }
    }

    /// Finalize WebView/OAuth login and return whether session is ready for home.
    @discardableResult
    func completeLoginAwaitingResult(
        from webView: WKWebView,
        method: FireLastLoginMethod? = nil
    ) async -> Bool {
        guard !isSyncingLoginSession else {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: "auth.login",
                message: "completeLogin ignored; already syncing"
            )
            return session.readiness.canReadAuthenticatedApi
        }

        isSyncingLoginSession = true
        defer { isSyncingLoginSession = false }

        do {
            return try await FireAPMManager.shared.withSpan(.authLoginSync) {
                let loginCoordinator = try await loginCoordinatorValue()
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                let readiness = try await loginCoordinator.probeLoginSyncReadiness(from: webView)
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "completeLogin probe ready=\(readiness.isReady) username=\(readiness.username ?? "nil") authCookies=\(readiness.hasAuthCookies) bootstrap=\(readiness.hasBootstrapHTML) score=\(readiness.preferredBootstrapScore)"
                )
                let session = try await loginCoordinator.completeLogin(from: webView)
                // Prefer starting MessageBus when bootstrap already made it possible.
                await applySession(session, activateMessageBus: true)
                if let method {
                    try await persistLastLoginMethod(method, sessionStore: sessionStore)
                }
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(true)
                FireCfClearanceRefreshService.shared.updateSession(
                    session,
                    loginCoordinator: loginCoordinator
                )
                // fluxdo finally: cookies trusted → enter home immediately.
                // App-state refresh must not block login-ready UI forever.
                setAuthPresentationState(nil)
                canSyncLoginSession = false
                cachedLoginSyncReadiness = nil
                Task { [weak self] in
                    guard let self else { return }
                    try? await sessionStore.triggerAppStateRefresh(
                        .loginCompleted,
                        handler: self.appStateRefreshCoordinator
                    )
                    await self.ensureMessageBusActiveIfPossible()
                }
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "completeLogin finished canReadAuth=\(session.readiness.canReadAuthenticatedApi)"
                )
                return session.readiness.canReadAuthenticatedApi
            }
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "error",
                target: "auth.login",
                message: "completeLogin failed: \(error.localizedDescription)"
            )
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return session.readiness.canReadAuthenticatedApi
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func completeMinimalLogin(
        from webView: WKWebView,
        identifier: String,
        password: String,
        rememberCredential: Bool
    ) {
        guard !isSyncingLoginSession else {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: "auth.login",
                message: "completeMinimalLogin ignored; already syncing"
            )
            return
        }

        isSyncingLoginSession = true
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "completeMinimalLogin capture-from-webView start remember=\(rememberCredential)"
        )
        Task {
            do {
                let loginCoordinator = try await loginCoordinatorValue()
                let captured = try await loginCoordinator.captureJsLoginState(
                    from: webView,
                    identifier: identifier
                )
                await completeMinimalLogin(
                    captured: captured,
                    password: password,
                    rememberCredential: rememberCredential,
                    alreadyMarkedSyncing: true
                )
            } catch {
                isSyncingLoginSession = false
                FireAPMManager.shared.recordBreadcrumb(
                    level: "error",
                    target: "auth.login",
                    message: "completeMinimalLogin capture failed: \(error.localizedDescription)"
                )
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Finalize password login from an already-captured WebView cookie snapshot.
    /// Callers should dismiss captcha UI first and show host-owned sync loading.
    func completeMinimalLogin(
        captured: FireCapturedLoginState,
        password: String,
        rememberCredential: Bool,
        alreadyMarkedSyncing: Bool = false
    ) async {
        if !alreadyMarkedSyncing {
            guard !isSyncingLoginSession else {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: "auth.login",
                    message: "completeMinimalLogin(captured) ignored; already syncing"
                )
                return
            }
            isSyncingLoginSession = true
        }

        let identifier = (captured.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "completeMinimalLogin start remember=\(rememberCredential) identifier_present=\(!identifier.isEmpty)"
        )

        defer { isSyncingLoginSession = false }

        do {
            try await FireAPMManager.shared.withSpan(.authLoginSync) {
                let loginCoordinator = try await loginCoordinatorValue()
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                let session = try await loginCoordinator.completeJsLogin(captured)
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "completeJsLogin ok canReadAuth=\(session.readiness.canReadAuthenticatedApi) loginPhase=\(String(describing: session.loginPhase))"
                )
                await applySession(session, activateMessageBus: true)
                try await persistLastLoginMethod(.password, sessionStore: sessionStore)
                if rememberCredential, !identifier.isEmpty {
                    try await sessionStore.saveLoginCredential(
                        username: identifier,
                        password: password
                    )
                    savedLoginCredential = try await sessionStore.loadSavedCredential()
                } else if !rememberCredential {
                    try await sessionStore.clearSavedCredential()
                    savedLoginCredential = nil
                }
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(true)
                // fluxdo finally: trusted cookies are enough to leave the login UI.
                setAuthPresentationState(nil)
                canSyncLoginSession = false
                cachedLoginSyncReadiness = nil
                Task { [weak self] in
                    guard let self else { return }
                    try? await sessionStore.triggerAppStateRefresh(
                        .loginCompleted,
                        handler: self.appStateRefreshCoordinator
                    )
                    await self.ensureMessageBusActiveIfPossible()
                }
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "completeMinimalLogin finished successfully"
                )
            }
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "error",
                target: "auth.login",
                message: "completeMinimalLogin failed: \(error.localizedDescription)"
            )
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func classifyWebViewLoginResult(
        _ result: WebViewLoginJsResultState
    ) async throws -> WebViewLoginDecisionState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.classifyWebViewLoginResult(result)
    }

    func classifyLoginResult(
        phase: WebViewLoginPhaseState,
        status: UInt16,
        body: String
    ) async throws -> WebViewLoginDecisionState {
        let result = WebViewLoginJsResultState(
            phase: phase,
            status: status,
            body: body
        )
        return try await classifyWebViewLoginResult(result)
    }

    func recoverLoginCloudflareChallenge(in webView: WKWebView) async throws {
        let sessionStore = try await sessionStoreValue()
        try await completeLoginCloudflareChallenge(sessionStore: sessionStore)
        try await Task.sleep(for: .milliseconds(1_500))
        let loginCoordinator = try await loginCoordinatorValue()
        try await loginCoordinator.primeCookies(
            into: webView,
            targetURL: URL(string: "https://linux.do/")
        )
    }

    func ensureCloudflareClearance() async -> Bool {
        do {
            let sessionStore = try await sessionStoreValue()
            // Do not trust jar clearance that CF recently rejected (cold start / IP drift).
            if try await sessionStore.cloudflareClearanceIsTrusted() {
                return true
            }

            try await completeLoginCloudflareChallenge(sessionStore: sessionStore)
            try await Task.sleep(for: .milliseconds(1_500))
            return try await sessionStore.cloudflareClearanceIsTrusted()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loginCoordinatorForDialog() async throws -> FireWebViewLoginCoordinator {
        try await loginCoordinatorValue()
    }

    func probeLoginSyncReadiness(from webView: WKWebView) async throws -> FireLoginSyncReadiness {
        let loginCoordinator = try await loginCoordinatorValue()
        return try await loginCoordinator.probeLoginSyncReadiness(from: webView)
    }

    private func completeLoginCloudflareChallenge(
        sessionStore: FireSessionStore
    ) async throws {
        let challengeCoordinator = FireCloudflareChallengeCoordinator(sessionStore: sessionStore)
        let result = await challengeCoordinator.completeManualVerification(originURL: "https://linux.do/")
        guard
            result.completed,
            let freshCfClearance = result.freshCfClearance?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !freshCfClearance.isEmpty
        else {
            throw FireLoginPreparationError.cloudflareVerificationIncomplete
        }

        let session = try await sessionStore.completeCloudflareChallenge(
            cookies: result.cookies,
            freshCfClearance: freshCfClearance,
            browserUserAgent: result.browserUserAgent
        )
        guard session.cookies.cfClearance == freshCfClearance else {
            throw FireLoginPreparationError.cloudflareVerificationIncomplete
        }
    }

    func dismissAuthPresentation() {
        canSyncLoginSession = false
        cachedLoginSyncReadiness = nil
        setAuthPresentationState(nil)
    }

    func prepareAuthWebView(_ webView: WKWebView) {
        guard webView.url == nil else {
            return
        }

        let targetURL = authPresentationURL
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let sessionStore = try await sessionStoreValue()
                let replayEntries = try await sessionStore.cookieReplayQueue()
                if !replayEntries.isEmpty {
                    let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                    for entry in replayEntries {
                        guard let cookieURL = URL(string: entry.url) else {
                            continue
                        }
                        let cookies = HTTPCookie.cookies(
                            withResponseHeaderFields: ["Set-Cookie": entry.rawSetCookie],
                            for: cookieURL
                        )
                        for cookie in cookies {
                            await setWebKitCookie(cookie, in: cookieStore)
                        }
                    }
                    try await sessionStore.clearCookieReplayQueue()
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            guard webView.url == nil else {
                return
            }
            webView.load(URLRequest(url: targetURL))
        }
    }

    func saveLoginCredential(username: String, password: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let sessionStore = try await sessionStoreValue()
                try await sessionStore.saveLoginCredential(username: username, password: password)
                savedLoginCredential = try await sessionStore.loadSavedCredential()
            } catch {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: Self.authDiagnosticsLogTarget,
                    message: "failed to persist login credential: \(error.localizedDescription)"
                )
            }
        }
    }

    private func persistLastLoginMethod(
        _ method: FireLastLoginMethod,
        sessionStore: FireSessionStore
    ) async throws {
        try await sessionStore.saveLastLoginMethod(method)
        lastLoginMethod = method
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: Self.authDiagnosticsLogTarget,
            message: "recorded last login method=\(method.rawValue)"
        )
    }

    func recordLoginFingerprintDone() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let sessionStore = try await sessionStoreValue()
                await sessionStore.recordFingerprintDone()
            } catch {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: Self.authDiagnosticsLogTarget,
                    message: "failed to record fingerprint completion: \(error.localizedDescription)"
                )
            }
        }
    }

    func refreshBootstrap() {
        Task {
            do {
                try await FireAPMManager.shared.withSpan(.bootstrapRefresh) {
                    let sessionStore = try await sessionStoreValue()
                    errorMessage = nil
                    await applySession(try await sessionStore.refreshBootstrap())
                    await refreshHomeFeedIfPossible(force: false)
                }
            } catch {
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func logout() {
        guard !isLoggingOut else {
            return
        }

        isLoggingOut = true
        // Explicit logout must never trigger mid-session / session-expired auto-login.
        didRequestExplicitLogout = true
        cancelMidSessionReauth(reason: "explicit_logout")

        Task {
            defer { isLoggingOut = false }

            do {
                let loginCoordinator = try await loginCoordinatorValue()
                stopMessageBus()
                errorMessage = nil
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
                await applySession(try await loginCoordinator.logout())
                let sessionStore = try await sessionStoreValue()
                try await sessionStore.triggerAppStateRefresh(.logoutCompleted)
                canSyncLoginSession = false
                cachedLoginSyncReadiness = nil
                clearTopicState()
                notificationStore?.reset()
                updateWidgetData()
            } catch {
                do {
                    let loginCoordinator = try await loginCoordinatorValue()
                    FireCfClearanceRefreshService.shared.setLoginStateConfirmed(false)
                    await applySession(
                        try await loginCoordinator.logoutLocalAndClearPlatformCookies(
                            preserveCfClearance: true
                        )
                    )
                    canSyncLoginSession = false
                    cachedLoginSyncReadiness = nil
                    clearTopicState()
                    notificationStore?.reset()
                    updateWidgetData()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Topic list

    func selectTopicKind(_ kind: TopicListKindState) {
        homeFeedStore?.selectTopicKind(kind)
    }

    func selectHomeCategory(_ categoryId: UInt64?) {
        homeFeedStore?.selectHomeCategory(categoryId)
    }

    func addHomeTag(_ tag: String) {
        homeFeedStore?.addHomeTag(tag)
    }

    func removeHomeTag(_ tag: String) {
        homeFeedStore?.removeHomeTag(tag)
    }

    func clearHomeTags() {
        homeFeedStore?.clearHomeTags()
    }

    var selectedHomeCategoryPresentation: FireTopicCategoryPresentation? {
        homeFeedStore?.selectedHomeCategoryPresentation
    }

    func refreshTopics() {
        homeFeedStore?.refreshTopics()
    }

    func refreshTopicsAsync() async {
        await homeFeedStore?.refreshTopicsAsync()
    }

    func loadMoreTopics() {
        homeFeedStore?.loadMoreTopics()
    }

    func patchHomeTopicCounts(from detail: TopicDetailState) {
        homeFeedStore?.patchTopicCounts(from: detail)
    }

    func loadTopicDetail(
        topicId: UInt64,
        topicSlug: String? = nil,
        targetPostNumber: UInt32? = nil,
        force: Bool = false
    ) async {
        await topicDetailStore?.loadTopicDetail(
            topicId: topicId,
            topicSlug: topicSlug,
            targetPostNumber: targetPostNumber,
            force: force
        )
    }

    func clearTopicDetailAnchor(topicId: UInt64) {
        topicDetailStore?.clearTopicDetailAnchor(topicId: topicId)
    }

    func topicDetail(for topicId: UInt64) -> TopicDetailState? {
        topicDetailStore?.topicDetail(for: topicId)
    }

    func topicPresenceUsers(for topicId: UInt64) -> [TopicPresenceUserState] {
        topicDetailStore?.topicPresenceUsers(for: topicId) ?? []
    }

    func isLoadingTopic(topicId: UInt64) -> Bool {
        topicDetailStore?.isLoadingTopic(topicId: topicId) ?? false
    }

    func isLoadingMoreTopicPosts(topicId: UInt64) -> Bool {
        topicDetailStore?.isLoadingMoreTopicPosts(topicId: topicId) ?? false
    }

    func hasMoreTopicPosts(topicId: UInt64) -> Bool {
        topicDetailStore?.hasMoreTopicPosts(topicId: topicId) ?? false
    }

    // MARK: - Topic detail lifecycle

    func beginTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        topicDetailStore?.beginTopicDetailLifecycle(topicId: topicId, ownerToken: ownerToken)
    }

    func endTopicDetailLifecycle(topicId: UInt64, ownerToken: String) {
        topicDetailStore?.endTopicDetailLifecycle(
            topicId: topicId,
            ownerToken: ownerToken,
            visibleTopicIDs: currentVisibleTopicIDs()
        )
    }

    func retainedTopicDetailIDs(visibleTopicIDs: Set<UInt64>) -> Set<UInt64> {
        topicDetailStore?.retainedTopicDetailIDs(visibleTopicIDs: visibleTopicIDs)
            ?? visibleTopicIDs
    }

    // MARK: - Topic detail MessageBus subscription

    func maintainTopicDetailSubscription(topicId: UInt64, ownerToken: String) async {
        await topicDetailStore?.maintainTopicDetailSubscription(
            topicId: topicId,
            ownerToken: ownerToken
        )
    }

    // MARK: - Write interactions

    func isSubmittingReply(topicId: UInt64) -> Bool {
        topicDetailStore?.isSubmittingReply(topicId: topicId) ?? false
    }

    func isMutatingPost(postId: UInt64) -> Bool {
        topicDetailStore?.isMutatingPost(postId: postId) ?? false
    }

    func categoryPresentation(for categoryID: UInt64?) -> FireTopicCategoryPresentation? {
        if let category = homeFeedStore?.categoryPresentation(for: categoryID) {
            return category
        }
        guard let categoryID else { return nil }
        return session.bootstrap.categories.first(where: { $0.id == categoryID })
    }

    func allCategories() -> [FireTopicCategoryPresentation] {
        homeFeedStore?.allCategories ?? session.bootstrap.categories
    }

    func topTags() -> [String] {
        homeFeedStore?.topTags ?? session.bootstrap.topTags
    }

    var canTagTopics: Bool {
        homeFeedStore?.canTagTopics ?? session.bootstrap.canTagTopics
    }

    var canStartAuthenticatedMutation: Bool {
        session.readiness.canReadAuthenticatedApi
    }

    var boundTopicDetailStore: FireTopicDetailStore? {
        topicDetailStore
    }

    func fetchFilteredTopicList(query: TopicListQueryState) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchTopicList(query: query)
    }

    func fetchPrivateMessages(
        kind: TopicListKindState,
        page: UInt32? = nil
    ) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchTopicList(
            query: TopicListQueryState(
                kind: kind,
                page: page,
                topicIds: [],
                order: nil,
                ascending: nil,
                categorySlug: nil,
                categoryId: nil,
                parentCategorySlug: nil,
                tag: nil,
                additionalTags: [],
                matchAllTags: false
            )
        )
    }

    func enabledReactionOptions() -> [FireReactionOption] {
        FireTopicPresentation.enabledReactionOptions(from: session.bootstrap.enabledReactionIds)
    }

    func submitReply(
        topicId: UInt64,
        raw: String,
        replyToPostNumber: UInt32?
    ) async throws {
        guard let topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        try await topicDetailStore.submitReply(
            topicId: topicId,
            raw: raw,
            replyToPostNumber: replyToPostNumber
        )
    }

    func createTopic(
        title: String,
        raw: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws -> UInt64 {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        guard !trimmedRaw.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        let sessionStore = try await sessionStoreValue()
        guard canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            errorMessage = nil
            let topicID = try await performWriteWithCloudflareRetry {
                try await sessionStore.createTopic(
                    title: trimmedTitle,
                    raw: trimmedRaw,
                    categoryID: categoryID,
                    tags: tags
                )
            }
            await syncSessionSnapshotIfAvailable(from: sessionStore)
            await refreshHomeFeedIfPossible(force: true)
            return topicID
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func createPrivateMessage(
        title: String,
        raw: String,
        targetRecipients: [String]
    ) async throws -> UInt64 {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipients = targetRecipients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedTitle.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        guard !trimmedRaw.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }
        guard !recipients.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        let sessionStore = try await sessionStoreValue()
        guard canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            errorMessage = nil
            let topicID = try await performWriteWithCloudflareRetry {
                try await sessionStore.createPrivateMessage(
                    title: trimmedTitle,
                    raw: trimmedRaw,
                    targetRecipients: recipients
                )
            }
            await syncSessionSnapshotIfAvailable(from: sessionStore)
            return topicID
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func updateTopic(
        topicID: UInt64,
        title: String,
        categoryID: UInt64,
        tags: [String]
    ) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw FireTopicInteractionError.emptyReply
        }

        let sessionStore = try await sessionStoreValue()
        guard canStartAuthenticatedMutation else {
            throw FireTopicInteractionError.requiresAuthenticatedWrite
        }

        do {
            errorMessage = nil
            try await performWriteWithCloudflareRetry {
                try await sessionStore.updateTopic(
                    topicID: topicID,
                    title: trimmedTitle,
                    categoryID: categoryID,
                    tags: tags
                )
            }
            await syncSessionSnapshotIfAvailable(from: sessionStore)
            await refreshHomeFeedIfPossible(force: true)
            await topicDetailStore?.refreshTopicDetailAfterMutation(topicId: topicID)
        } catch {
            _ = await handleInteractionError(error)
            throw error
        }
    }

    func fetchPost(postID: UInt64) async throws -> TopicPostState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchPost(postID: postID)
    }

    func updatePost(
        topicID: UInt64,
        postID: UInt64,
        raw: String,
        editReason: String? = nil
    ) async throws -> TopicPostState {
        guard let topicDetailStore else {
            throw FireTopicInteractionError.unavailable
        }
        return try await topicDetailStore.updatePost(
            topicID: topicID,
            postID: postID,
            raw: raw,
            editReason: editReason
        )
    }

    func fetchDrafts(
        offset: UInt32? = nil,
        limit: UInt32? = nil
    ) async throws -> DraftListResponseState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchDrafts(offset: offset, limit: limit)
    }

    func fetchReadHistory(page: UInt32? = nil) async throws -> TopicListState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchReadHistory(page: page)
    }

    func fetchDraft(draftKey: String) async throws -> DraftState? {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.fetchDraft(draftKey: draftKey)
    }

    func saveDraft(
        draftKey: String,
        data: DraftDataState,
        sequence: UInt32
    ) async throws -> UInt32 {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry {
            try await sessionStore.saveDraft(
                draftKey: draftKey,
                data: data,
                sequence: sequence
            )
        }
    }

    func deleteDraft(
        draftKey: String,
        sequence: UInt32? = nil
    ) async throws {
        let sessionStore = try await sessionStoreValue()
        try await performWriteWithCloudflareRetry {
            try await sessionStore.deleteDraft(draftKey: draftKey, sequence: sequence)
        }
    }

    func uploadImage(
        fileName: String,
        mimeType: String?,
        bytes: Data
    ) async throws -> UploadResultState {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry {
            try await sessionStore.uploadImage(
                fileName: fileName,
                mimeType: mimeType,
                bytes: bytes
            )
        }
    }

    func lookupUploadUrls(shortUrls: [String]) async throws -> [ResolvedUploadUrlState] {
        let sessionStore = try await sessionStoreValue()
        return try await performWriteWithCloudflareRetry {
            try await sessionStore.lookupUploadUrls(shortUrls: shortUrls)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func updateTopLevelAPMRoute(selectedTab: Int, isAuthenticated: Bool) {
        let route: String
        if !isAuthenticated {
            route = "session.onboarding"
        } else {
            switch selectedTab {
            case 0:
                route = "tab.home"
            case 1:
                route = "tab.notifications"
            case 2:
                route = "tab.profile"
            default:
                route = "tab.unknown"
            }
        }
        topLevelAPMRoute = route
        FireAPMManager.shared.setCurrentRoute(route)
    }

    func restoreTopLevelAPMRoute() {
        FireAPMManager.shared.setCurrentRoute(topLevelAPMRoute)
    }

    func setAPMRoute(_ route: String) {
        FireAPMManager.shared.setCurrentRoute(route)
    }

    // MARK: - MessageBus lifecycle

    private func startMessageBus() async {
        guard let sessionStore else { return }
        guard session.readiness.canOpenMessageBus else { return }
        guard !isMessageBusActive else { return }

        messageBusRetryTask?.cancel()
        messageBusRetryTask = nil

        let coordinator = FireMessageBusCoordinator { [weak self] event in
            self?.handleMessageBusEvent(event)
        }
        messageBusCoordinator = coordinator

        do {
            _ = try await FireAPMManager.shared.withSpan(.messageBusStart) {
                try await sessionStore.startMessageBus(handler: coordinator)
            }
            isMessageBusActive = true
            messageBusStartRetryCount = 0
            clearMessageBusError()
        } catch {
            messageBusCoordinator = nil
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            errorMessage = Self.messageBusErrorPrefix + error.localizedDescription
            scheduleMessageBusRetry()
        }
    }

    private func stopMessageBus() {
        messageBusRetryTask?.cancel()
        messageBusRetryTask = nil
        messageBusStartRetryCount = 0
        notificationStore?.cancelScheduledRefresh()
        homeFeedStore?.handleMessageBusStopped()
        topicDetailStore?.handleMessageBusStopped()
        clearMessageBusError()
        guard isMessageBusActive else { return }
        messageBusCoordinator = nil
        isMessageBusActive = false
        guard let sessionStore else { return }
        Task { try? await sessionStore.stopMessageBus(clearSubscriptions: true) }
    }

    private func handleMessageBusEvent(_ event: MessageBusEventState) {
        switch event.kind {
        case .topicList:
            homeFeedStore?.handleTopicListMessageBusEvent(event)

        case .topicDetail, .topicReaction, .presence:
            topicDetailStore?.handleMessageBusEvent(event)

        case .notification:
            notificationStore?.scheduleStateRefresh()

        case .notificationAlert:
            break

        case .unknown:
            break
        }
    }

    func beginTopicReplyPresence(topicId: UInt64) {
        topicDetailStore?.beginTopicReplyPresence(topicId: topicId)
    }

    func endTopicReplyPresence(topicId: UInt64) async {
        await topicDetailStore?.endTopicReplyPresence(topicId: topicId)
    }

    // MARK: - Private helpers

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

    private func preloadLoginCoordinator() async throws {
        if let loginCoordinatorPreloader {
            try await loginCoordinatorPreloader()
            return
        }

        _ = try await loginCoordinatorValue()
    }

    private func warmLoginNetworkAccess() async {
        if let loginNetworkWarmup {
            await loginNetworkWarmup()
            return
        }

        do {
            try await prepareLoginNetworkAccess()
        } catch {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: "auth.login",
                message: "login network warmup failed: \(error.localizedDescription)"
            )
        }
    }

    private func refreshTopicsIfPossible(force: Bool) async {
        await refreshHomeFeedIfPossible(force: force)
    }

    var authPresentationURL: URL {
        loginURL
    }

    private func clearTopicState() {
        homeFeedStore?.reset(resetTopicKind: true)
        topicDetailStore?.reset()
    }

    private func finishInitialStateLoading(generation: UInt64) {
        guard initialStateLoadGeneration == generation else {
            return
        }

        initialStateLoadingDelayTask?.cancel()
        initialStateLoadingDelayTask = nil
        isBootstrappingSession = false
        isStartupLoadingVisible = false
        initialStateTask = nil
    }

    private func applySession(_ session: SessionState, activateMessageBus: Bool = true) async {
        let wasAuthenticated = self.session.readiness.canReadAuthenticatedApi
        let shouldSyncNativeCookies = session.cookies != self.session.cookies
            || session.bootstrap.baseUrl != self.session.bootstrap.baseUrl
        self.session = session
        if shouldSyncNativeCookies {
            session.syncCookiesToNativeStorage()
        }
        homeFeedStore?.applySession(session)
        topicDetailStore?.applySession(session)

        let isAuthenticated = session.readiness.canReadAuthenticatedApi
        if wasAuthenticated && !isAuthenticated && !didRequestExplicitLogout {
            // Raise the reauth hold synchronously so RootCoordinator's next main-runloop
            // auth sink keeps the main shell mounted for Google headless recovery.
            scheduleMidSessionReauthAfterPassiveDeauth()
        }

        if isAuthenticated {
            await notificationStore?.syncStateFromRuntimeIfAvailable()
        } else {
            notificationStore?.reset()
            updateWidgetData()
        }

        // Reconcile MessageBus lifecycle
        if session.readiness.canOpenMessageBus && activateMessageBus && !isMessageBusActive {
            await startMessageBus()
        } else if !session.readiness.canOpenMessageBus && isMessageBusActive {
            stopMessageBus()
        } else if !session.readiness.canOpenMessageBus {
            stopMessageBus()
        }

        if let coordinator = try? await loginCoordinatorValue() {
            FireCfClearanceRefreshService.shared.updateSession(
                session,
                loginCoordinator: coordinator,
                onSessionRefreshed: { [weak self] updatedSession in
                    guard let self else { return }
                    await self.cfClearanceDidRefresh(updatedSession)
                }
            )
        }
    }

    func cfClearanceDidRefresh(_ updatedSession: SessionState) async {
        await applySession(updatedSession)
    }

    func refreshLoginSyncReadiness(from webView: WKWebView) {
        loginSyncReadinessTask?.cancel()
        loginSyncReadinessTask = Task { [weak self] in
            guard let self else { return }
            do {
                let coordinator = try await loginCoordinatorValue()
                let readiness = try await coordinator.probeLoginSyncReadiness(from: webView)
                guard !Task.isCancelled else { return }
                let previous = canSyncLoginSession
                cachedLoginSyncReadiness = readiness.isReady
                    ? CachedLoginSyncReadiness(
                        currentURL: webView.url?.absoluteString,
                        readiness: readiness
                    )
                    : nil
                canSyncLoginSession = readiness.isReady
                if previous != readiness.isReady {
                    FireAPMManager.shared.recordBreadcrumb(
                        target: "auth.login",
                        message: readiness.isReady
                            ? "login sync readiness satisfied"
                            : "login sync readiness cleared"
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                canSyncLoginSession = false
                cachedLoginSyncReadiness = nil
            }
        }
    }

    private func scheduleMessageBusRetry() {
        guard session.readiness.canOpenMessageBus else { return }
        guard !isMessageBusActive else { return }
        guard messageBusStartRetryCount < 3 else { return }

        messageBusStartRetryCount += 1
        let retryDelay = Duration.seconds(Double(messageBusStartRetryCount * 2))
        messageBusRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: retryDelay)
            } catch {
                return
            }
            guard let self else { return }
            self.messageBusRetryTask = nil
            await self.startMessageBus()
        }
    }

    private func clearMessageBusError() {
        if errorMessage?.hasPrefix(Self.messageBusErrorPrefix) == true {
            errorMessage = nil
        }
    }

    /// Write-path CF wrapper. **Passthrough** — does not wait or present.
    ///
    /// Rust already fails writes quickly with `CloudflareChallengeInProgress`
    /// while a challenge is active. Host-side wait/retry would hang composer
    /// actions for up to minutes with no UI feedback; callers should surface
    /// the error and let the user retry after verification.
    func performWriteWithCloudflareRetry<T>(
        operationDescription: String = "执行当前操作",
        originURL: URL? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        _ = operationDescription
        _ = originURL
        return try await operation()
    }

    /// Read-path join/retry helper for Cloudflare errors. **Does not present** UI.
    ///
    /// - `in_progress`: wait for the host presentation gate (Rust handler already
    ///   owns the WebView), settle jar merge, then retry `work` once.
    /// - other CF reasons: rethrow for banners / explicit manual verify.
    ///
    /// `originURL` is retained for call-site compatibility and diagnostics only.
    func performWithCloudflareRecovery<T>(
        operation: String,
        originURL: URL? = nil,
        work: @escaping () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch {
            guard Self.isCloudflareChallengeError(error) else {
                throw error
            }
            let reason = Self.cloudflareChallengeReason(from: error)
            switch Self.cloudflareRecoveryAction(forReason: reason) {
            case .waitThenRetry:
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.cf",
                    message: "recovery wait-then-retry operation=\(operation) reason=\(reason) origin=\(originURL?.absoluteString ?? "nil")"
                )
                await Self.awaitCloudflareChallengeQuietPeriod()
                return try await work()
            case .rethrow:
                throw error
            }
        }
    }

    /// Host recovery policy for a normalized CF reason token (read path).
    /// Automatic paths never present UI (`waitThenRetry` / `rethrow` only).
    enum CloudflareRecoveryAction: Equatable {
        case waitThenRetry
        case rethrow
    }

    nonisolated static func cloudflareRecoveryAction(
        forReason reason: String
    ) -> CloudflareRecoveryAction {
        switch reason {
        case "in_progress":
            return .waitThenRetry
        default:
            // required / failed / cancelled / cooldown / background_suppressed:
            // surface to UI. Present only via Rust handler or explicit manual APIs.
            return .rethrow
        }
    }

    /// Wait for an in-flight host challenge presentation, then briefly settle.
    /// Used on read paths when Rust blocks concurrent traffic with `in_progress`.
    static func awaitCloudflareChallengeQuietPeriod(
        appearTimeout: Duration = .seconds(2),
        presentationTimeout: Duration = .seconds(120),
        settle: Duration = .milliseconds(500)
    ) async {
        await FireCloudflareChallengePresentationGate.awaitPresentationAppearance(
            timeout: appearTimeout
        )
        if FireCloudflareChallengePresentationGate.isPresentationInFlight {
            await FireCloudflareChallengePresentationGate.awaitActivePresentationIfAny(
                timeout: presentationTimeout
            )
        }
        try? await Task.sleep(for: settle)
    }

    nonisolated static func isCloudflareChallengeError(_ error: Error) -> Bool {
        if let fireError = error as? FireUniFfiError {
            if case .CloudflareChallenge = fireError {
                return true
            }
        }
        let message = String(describing: error).lowercased()
        return message.contains("cloudflare challenge")
    }

    nonisolated static func cloudflareChallengeReason(from error: Error) -> String {
        if let fireError = error as? FireUniFfiError,
           case let .CloudflareChallenge(reason) = fireError {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        let message = String(describing: error)
        for token in ["in_progress", "cooldown", "cancelled", "failed", "background_suppressed", "required"] {
            if message.contains("(\(token))") || message.contains(token) {
                return token
            }
        }
        return "required"
    }

    /// Onboarding entry used when the authenticated shell loses auth.
    /// Explicit logout always returns `.signedOut` (no auto-login).
    /// Passive / mid-session invalidation returns `.sessionExpired` so headless
    /// Google can auto-login on the onboarding host as a fallback path.
    func deauthOnboardingEntry() -> FireOnboardingEntry {
        if didRequestExplicitLogout {
            didRequestExplicitLogout = false
            return .signedOut
        }
        return .sessionExpired
    }

    /// Cancel an in-flight mid-session reauth (overlay cancel / explicit logout).
    func cancelMidSessionReauth(reason: String = "user_cancel") {
        guard isMidSessionReauthInFlight || midSessionReauthEngine != nil else { return }
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: Self.authDiagnosticsLogTarget,
            message: "mid-session reauth cancelled reason=\(reason)"
        )
        if let engine = midSessionReauthEngine {
            engine.cancel()
            return
        }
        finishMidSessionReauth(success: false)
    }

    /// Read-side recovery for transient `LoginRequired` errors observed during
    /// passive reads (home feed, topic detail) and other in-app requests.
    ///
    /// Recovery order:
    /// 1. Single-flight host cookie resync per session epoch (WebKit may be ahead
    ///    of the shared Rust jar after `_t` / `_forum_session` rotation).
    /// 2. If the last login method is headless-capable (currently Google), run
    ///    mid-session headless reauth under a loading overlay and keep the main
    ///    shell mounted so the caller can retry the original request in place.
    ///
    /// - Returns: `true` when recovery succeeded and the caller should retry once.
    @discardableResult
    func attemptReadPathLoginRecovery(
        operation: String,
        error: Error
    ) async -> Bool {
        guard case FireUniFfiError.LoginRequired = error else {
            return false
        }

        if await attemptHostCookieResyncRecovery(operation: operation) {
            return true
        }

        return await attemptMidSessionHeadlessReauth(operation: operation)
    }

    private func attemptHostCookieResyncRecovery(operation: String) async -> Bool {
        let logger = await authDiagnosticsLogger()

        let beforeEpoch: UInt64
        do {
            beforeEpoch = try await currentSessionEpoch()
        } catch {
            logger?.warning(
                "read-path resync skipped operation=\(operation) reason=epoch_unavailable error=\(error.localizedDescription)"
            )
            return false
        }

        if readPathLoginRecoveryAttemptedEpochs.contains(beforeEpoch) {
            logger?.notice(
                "read-path resync skipped operation=\(operation) reason=already_attempted epoch=\(beforeEpoch)"
            )
            return false
        }

        if let existingTask = readPathLoginRecoveryTask,
            readPathLoginRecoveryEpoch == beforeEpoch {
            return await existingTask.value
        }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.runReadPathLoginRecovery(
                operation: operation,
                beforeEpoch: beforeEpoch
            )
        }
        readPathLoginRecoveryTask = task
        readPathLoginRecoveryEpoch = beforeEpoch
        defer {
            if readPathLoginRecoveryEpoch == beforeEpoch {
                readPathLoginRecoveryTask = nil
                readPathLoginRecoveryEpoch = nil
            }
        }
        return await task.value
    }

    private func runReadPathLoginRecovery(
        operation: String,
        beforeEpoch: UInt64
    ) async -> Bool {
        readPathLoginRecoveryAttemptedEpochs.insert(beforeEpoch)
        let logger = await authDiagnosticsLogger()

        let coordinator: FireWebViewLoginCoordinator
        do {
            coordinator = try await loginCoordinatorValue()
        } catch {
            logger?.warning(
                "read-path resync skipped operation=\(operation) epoch=\(beforeEpoch) reason=no_coordinator error=\(error.localizedDescription)"
            )
            return false
        }

        let cookies: [PlatformCookieState]
        do {
            cookies = try await coordinator.platformCookiesForSessionResync()
        } catch {
            logger?.warning(
                "read-path resync failed operation=\(operation) epoch=\(beforeEpoch) reason=cookie_fetch_failed error=\(error.localizedDescription)"
            )
            return false
        }

        guard FireWebViewLoginCoordinator.containsActiveAuthCookies(in: cookies) else {
            logger?.notice(
                "read-path resync skipped operation=\(operation) epoch=\(beforeEpoch) reason=no_authoritative_webview_auth_cookies cookie_count=\(cookies.count)"
            )
            return false
        }

        let sessionStore: FireSessionStore
        do {
            sessionStore = try await sessionStoreValue()
        } catch {
            logger?.warning(
                "read-path resync skipped operation=\(operation) epoch=\(beforeEpoch) reason=no_session_store error=\(error.localizedDescription)"
            )
            return false
        }

        do {
            _ = try await sessionStore.applyPlatformCookies(cookies)
        } catch {
            logger?.warning(
                "read-path resync failed operation=\(operation) epoch=\(beforeEpoch) reason=apply_failed error=\(error.localizedDescription)"
            )
            return false
        }

        let afterEpoch: UInt64
        do {
            afterEpoch = try await sessionStore.currentSessionEpoch()
        } catch {
            logger?.warning(
                "read-path resync inconclusive operation=\(operation) epoch=\(beforeEpoch) reason=post_epoch_unavailable error=\(error.localizedDescription)"
            )
            return false
        }

        let didRotate = afterEpoch != beforeEpoch
        if didRotate {
            // Once the resync actually rotated us into a new auth epoch, the
            // older `attempted` markers no longer protect us from anything;
            // keep the set small so a long-lived session doesn't accumulate
            // stale markers.
            readPathLoginRecoveryAttemptedEpochs = readPathLoginRecoveryAttemptedEpochs
                .filter { $0 == afterEpoch }
            FireAPMManager.shared.recordBreadcrumb(
                target: Self.authDiagnosticsLogTarget,
                message: "read-path resync rotated auth operation=\(operation) before_epoch=\(beforeEpoch) after_epoch=\(afterEpoch) cookie_count=\(cookies.count)"
            )
            logger?.notice(
                "read-path resync rotated auth operation=\(operation) before_epoch=\(beforeEpoch) after_epoch=\(afterEpoch) cookie_count=\(cookies.count)"
            )
        } else {
            logger?.notice(
                "read-path resync no_change operation=\(operation) epoch=\(beforeEpoch) cookie_count=\(cookies.count)"
            )
        }
        return didRotate
    }

    /// Called from `applySession` when auth drops without an explicit logout.
    /// Starts Google headless recovery early enough for RootCoordinator to hold the shell.
    private func scheduleMidSessionReauthAfterPassiveDeauth() {
        if midSessionReauthTask != nil || isMidSessionReauthInFlight {
            return
        }

        let knownMethod = FireAutoLoginPlanner.midSessionHeadlessKind(
            lastLoginMethod: lastLoginMethod
        )
        // lastLoginMethod may not be loaded yet on a long-lived session; optimistically
        // hold and resolve eligibility inside the single-flight reauth task.
        guard knownMethod != nil || lastLoginMethod == nil else {
            return
        }

        isMidSessionReauthInFlight = true
        if midSessionReauthMessage == nil {
            if let knownMethod {
                midSessionReauthMessage = FireAutoLoginPlanner.loadingMessage(
                    for: .external(knownMethod)
                )
            } else {
                midSessionReauthMessage = "正在恢复登录…"
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.attemptMidSessionHeadlessReauth(operation: "session_deauth")
        }
    }

    /// Mid-session headless reauth for LoginRequired when cookie resync cannot help.
    /// Currently limited to providers in `FireAutoLoginPlanner.headlessExternalPool`
    /// (Google). Single-flight across the app so concurrent failing requests share
    /// one overlay + one OAuth attempt, then all retry.
    private func attemptMidSessionHeadlessReauth(operation: String) async -> Bool {
        if let existing = midSessionReauthTask {
            return await existing.value
        }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.runMidSessionHeadlessReauth(operation: operation)
        }
        midSessionReauthTask = task
        let result = await task.value
        if midSessionReauthTask != nil {
            midSessionReauthTask = nil
        }
        return result
    }

    private func runMidSessionHeadlessReauth(operation: String) async -> Bool {
        // Explicit logout wins over any in-flight recovery.
        guard !didRequestExplicitLogout, !isLoggingOut else {
            finishMidSessionReauth(success: false)
            return false
        }

        if lastLoginMethod == nil {
            await prepareLoginForm()
        }

        guard let method = FireAutoLoginPlanner.midSessionHeadlessKind(
            lastLoginMethod: lastLoginMethod
        ) else {
            let logger = await authDiagnosticsLogger()
            logger?.notice(
                "mid-session reauth skipped operation=\(operation) reason=method_ineligible last=\(String(describing: lastLoginMethod))"
            )
            finishMidSessionReauth(success: false)
            return false
        }

        guard let hostViewController = Self.topPresenterForMidSessionReauth() else {
            let logger = await authDiagnosticsLogger()
            logger?.warning(
                "mid-session reauth skipped operation=\(operation) reason=no_presenter"
            )
            finishMidSessionReauth(success: false)
            return false
        }

        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: Self.authDiagnosticsLogTarget,
            message: "mid-session reauth begin operation=\(operation) method=\(method.rawValue)"
        )

        isMidSessionReauthInFlight = true
        midSessionReauthMessage = FireAutoLoginPlanner.loadingMessage(for: .external(method))

        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // A proactive deauth hold may already have flipped inFlight without a waiter.
            if let previous = self.midSessionReauthContinuation {
                self.midSessionReauthContinuation = nil
                previous.resume(returning: false)
            }
            self.midSessionReauthContinuation = continuation

            let engine = FireHeadlessExternalLoginEngine(method: method, viewModel: self)
            self.midSessionReauthEngine = engine
            engine.onOutcome = { [weak self] outcome in
                guard let self else { return }
                self.handleMidSessionReauthOutcome(
                    outcome,
                    method: method,
                    presenter: hostViewController
                )
            }
            engine.start(in: hostViewController.view)
        }

        if succeeded {
            FireAPMManager.shared.recordBreadcrumb(
                level: "info",
                target: Self.authDiagnosticsLogTarget,
                message: "mid-session reauth succeeded operation=\(operation) method=\(method.rawValue)"
            )
        } else {
            FireAPMManager.shared.recordBreadcrumb(
                level: "warn",
                target: Self.authDiagnosticsLogTarget,
                message: "mid-session reauth failed operation=\(operation) method=\(method.rawValue)"
            )
        }
        return succeeded
    }

    private func handleMidSessionReauthOutcome(
        _ outcome: FireHeadlessExternalLoginEngine.Outcome,
        method: FireExternalLoginMethod,
        presenter: UIViewController
    ) {
        switch outcome {
        case .authenticated:
            guard let webView = midSessionReauthEngine?.currentWebView else {
                finishMidSessionReauth(success: false)
                return
            }
            midSessionReauthMessage = "正在同步登录态…"
            Task { @MainActor in
                let ok = await self.completeLoginAwaitingResult(
                    from: webView,
                    method: method.lastLoginMethod
                )
                self.finishMidSessionReauth(success: ok && self.session.readiness.canReadAuthenticatedApi)
            }

        case .needsUserInteraction:
            midSessionReauthMessage = FireAutoLoginPlanner.loadingMessage(for: .external(method))
                .replacingOccurrences(of: "正在通过", with: "请完成")
                .replacingOccurrences(of: "…", with: "")
            midSessionReauthEngine?.promote(from: presenter)

        case .failed:
            finishMidSessionReauth(success: false)

        case .cancelled:
            finishMidSessionReauth(success: false)
        }
    }

    private func finishMidSessionReauth(success: Bool) {
        midSessionReauthEngine?.teardown()
        midSessionReauthEngine = nil
        midSessionReauthMessage = nil
        isMidSessionReauthInFlight = false

        if let continuation = midSessionReauthContinuation {
            midSessionReauthContinuation = nil
            continuation.resume(returning: success)
        }
    }

    private static func topPresenterForMidSessionReauth() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private func currentSessionEpoch() async throws -> UInt64 {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.currentSessionEpoch()
    }

    @discardableResult
    func handleRecoverableSessionErrorIfNeeded(_ error: Error) async -> Bool {
        await handleStaleSessionResponseIfNeeded(error)
    }

    @discardableResult
    func handleStaleSessionResponseIfNeeded(_ error: Error) async -> Bool {
        guard case let FireUniFfiError.StaleSessionResponse(operation) = error else {
            return false
        }

        FireAPMManager.shared.recordBreadcrumb(
            target: Self.authDiagnosticsLogTarget,
            message: "discarded stale session response operation=\(operation)"
        )
        return true
    }

    @discardableResult
    func handleInteractionError(_ error: Error) async -> Bool {
        if await handleRecoverableSessionErrorIfNeeded(error) {
            return true
        }
        errorMessage = error.localizedDescription
        return false
    }

    private func authDiagnosticsLogger() async -> FireHostLogger? {
        if let sessionStore {
            return sessionStore.makeLogger(target: Self.authDiagnosticsLogTarget)
        }
        guard let sessionStore = try? await sessionStoreValue() else {
            return nil
        }
        return sessionStore.makeLogger(target: Self.authDiagnosticsLogTarget)
    }

    private func setWebKitCookie(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func setAuthPresentationState(_ state: FireAuthPresentationState?) {
        authPresentationState = state
    }

    func topicDetailLogger() -> FireHostLogger? {
        sessionStore?.makeLogger(target: Self.topicDetailLogTarget)
    }

    func topicRouteLogger() -> FireHostLogger? {
        sessionStore?.makeLogger(target: Self.topicRouteLogTarget)
    }

    func currentSessionStore() -> FireSessionStore? {
        sessionStore
    }

    func ensureMessageBusActiveIfPossible() async {
        guard !isMessageBusActive else { return }
        await startMessageBus()
    }

    func restartMessageBusAfterClearanceIfPossible() async {
        if isMessageBusActive {
            stopMessageBus()
        }
        await startMessageBus()
    }

    private func handleAppStateRefreshEvent(_ event: AppStateRefreshEventState) {
        if event.trigger == .cloudflareResolved {
            Task { @MainActor in
                self.homeFeedStore?.clearTopicLoadError()
                if self.session.readiness.canOpenMessageBus {
                    await self.restartMessageBusAfterClearanceIfPossible()
                }
            }
        }
    }

    private func handleClearanceResolved(_ event: CloudflareClearanceResolvedEventState) async {
        homeFeedStore?.clearTopicLoadError()
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.cf",
            message: "clearance resolved gen=\(event.generation) login=\(event.hasLoginSession) bus=\(event.canOpenMessageBus)"
        )
        if event.canOpenMessageBus || session.readiness.canOpenMessageBus {
            await restartMessageBusAfterClearanceIfPossible()
        }
        // Home topic list may still show a CF failure banner; force one refresh.
        _ = await refreshHomeFeedIfPossible(force: true)
    }

    @discardableResult
    func refreshHomeFeedIfPossible(force: Bool) async -> Bool {
        await homeFeedStore?.refreshTopicsIfPossible(force: force) ?? false
    }

    func pruneTopicDetailState(retainingVisibleTopicIDs visibleTopicIDs: Set<UInt64>) {
        topicDetailStore?.pruneInactiveTopicDetailState(
            retainingVisibleTopicIDs: visibleTopicIDs
        )
    }

    func currentVisibleTopicIDs() -> Set<UInt64> {
        homeFeedStore?.visibleTopicIDs ?? []
    }

    func syncSessionSnapshotIfAvailable(from sessionStore: FireSessionStore) async {
        if let snapshot = try? await sessionStore.snapshot() {
            await applySession(snapshot)
        }
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

    private func registerStateObserver(with sessionStore: FireSessionStore) async {
        await sessionStore.registerStateObserver(stateObserverCoordinator)
    }

    private func loginCoordinatorValue() async throws -> FireWebViewLoginCoordinator {
        if let loginCoordinator {
            return loginCoordinator
        }

        let sessionStore = try await sessionStoreValue()
        await configureAuthenticatedWriteHostResyncProvider(with: sessionStore)
        guard let loginCoordinator else {
            throw CancellationError()
        }
        return loginCoordinator
    }

    private func configureAuthenticatedWriteHostResyncProvider(
        with sessionStore: FireSessionStore
    ) async {
        let loginCoordinator: FireWebViewLoginCoordinator
        if let existingLoginCoordinator = self.loginCoordinator {
            loginCoordinator = existingLoginCoordinator
        } else {
            let newLoginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
            self.loginCoordinator = newLoginCoordinator
            loginCoordinator = newLoginCoordinator
        }

        await sessionStore.setAuthenticatedWriteHostResyncProvider { [weak loginCoordinator] in
            guard let loginCoordinator else {
                return nil
            }
            return try await loginCoordinator.platformCookiesForSessionResync()
        }

        if cloudflareChallengeHandler == nil {
            cloudflareChallengeHandler = FireCloudflareChallengeRuntimeHandler(
                sessionStore: sessionStore
            )
        }
        if let cloudflareChallengeHandler {
            try? await sessionStore.registerCloudflareChallengeHandler(
                cloudflareChallengeHandler
            )
        }
        if clearanceResolvedHandler == nil {
            clearanceResolvedHandler = FireClearanceResolvedRuntimeHandler { [weak self] event in
                await self?.handleClearanceResolved(event)
            }
        }
        if let clearanceResolvedHandler {
            try? await sessionStore.registerCloudflareClearanceResolvedHandler(
                clearanceResolvedHandler
            )
        }
        if cookieSelfHealingHandler == nil {
            cookieSelfHealingHandler = FireCookieSelfHealingRuntimeHandler(
                loginCoordinator: loginCoordinator
            )
        }
        if let cookieSelfHealingHandler {
            try? await sessionStore.registerCookieSelfHealingHandler(
                cookieSelfHealingHandler
            )
        }
    }

}
