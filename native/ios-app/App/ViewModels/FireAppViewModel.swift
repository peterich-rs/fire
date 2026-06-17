import Foundation
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
    @Published var isLoggingOut = false
    @Published private(set) var isStartupValidationComplete = false
    private var isStartupValidationInFlight = false

    // MARK: - Private

    private var sessionStore: FireSessionStore?
    private var loginCoordinator: FireWebViewLoginCoordinator?
    private var cloudflareChallengeHandler: FireCloudflareChallengeRuntimeHandler?
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
            _ = try await loginCoordinatorValue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openLogin() {
        guard authPresentationState == nil else { return }
        errorMessage = nil
        canSyncLoginSession = false
        cachedLoginSyncReadiness = nil
        setAuthPresentationState(.login)

        Task { await prepareLoginForm() }
    }

    func completeLogin(from webView: WKWebView) {
        guard !isSyncingLoginSession else {
            return
        }

        isSyncingLoginSession = true
        Task {
            defer { isSyncingLoginSession = false }

            do {
                try await FireAPMManager.shared.withSpan(.authLoginSync) {
                    let loginCoordinator = try await loginCoordinatorValue()
                    let sessionStore = try await sessionStoreValue()
                    errorMessage = nil
                    await applySession(
                        try await loginCoordinator.completeLogin(from: webView),
                        activateMessageBus: false
                    )
                    FireCfClearanceRefreshService.shared.setLoginStateConfirmed(true)
                    try await sessionStore.triggerAppStateRefresh(
                        .loginCompleted,
                        handler: appStateRefreshCoordinator
                    )
                    setAuthPresentationState(nil)
                    canSyncLoginSession = false
                    cachedLoginSyncReadiness = nil
                }
            } catch {
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func completeMinimalLogin(
        from webView: WKWebView,
        identifier: String,
        password: String,
        rememberCredential: Bool
    ) {
        guard !isSyncingLoginSession else {
            return
        }

        isSyncingLoginSession = true
        Task {
            defer { isSyncingLoginSession = false }

            do {
                try await FireAPMManager.shared.withSpan(.authLoginSync) {
                    let loginCoordinator = try await loginCoordinatorValue()
                    let sessionStore = try await sessionStoreValue()
                    errorMessage = nil
                    await applySession(
                        try await loginCoordinator.completeJsLogin(
                            from: webView,
                            identifier: identifier
                        ),
                        activateMessageBus: false
                    )
                    if rememberCredential {
                        try await sessionStore.saveLoginCredential(
                            username: identifier,
                            password: password
                        )
                        savedLoginCredential = try await sessionStore.loadSavedCredential()
                    } else {
                        try await sessionStore.clearSavedCredential()
                        savedLoginCredential = nil
                    }
                    FireCfClearanceRefreshService.shared.setLoginStateConfirmed(true)
                    try await sessionStore.triggerAppStateRefresh(
                        .loginCompleted,
                        handler: appStateRefreshCoordinator
                    )
                    setAuthPresentationState(nil)
                    canSyncLoginSession = false
                    cachedLoginSyncReadiness = nil
                }
            } catch {
                if await handleRecoverableSessionErrorIfNeeded(error) {
                    return
                }
                errorMessage = error.localizedDescription
            }
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
            if try await sessionStore.snapshot().readiness.hasCloudflareClearance {
                return true
            }

            try await completeLoginCloudflareChallenge(sessionStore: sessionStore)
            try await Task.sleep(for: .milliseconds(1_500))
            return try await sessionStore.snapshot().readiness.hasCloudflareClearance
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
        let shouldSyncNativeCookies = session.cookies != self.session.cookies
            || session.bootstrap.baseUrl != self.session.bootstrap.baseUrl
        self.session = session
        if shouldSyncNativeCookies {
            session.syncCookiesToNativeStorage()
        }
        homeFeedStore?.applySession(session)
        topicDetailStore?.applySession(session)

        if session.readiness.canReadAuthenticatedApi {
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

    func performWriteWithCloudflareRetry<T>(
        operationDescription: String = "执行当前操作",
        originURL: URL? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await operation()
    }

    func performWithCloudflareRecovery<T>(
        operation: String,
        originURL: URL? = nil,
        work: @escaping () async throws -> T
    ) async throws -> T {
        return try await work()
    }

    /// Read-side recovery for transient `LoginRequired` errors observed during
    /// passive reads (home feed, topic detail). Discourse occasionally rotates
    /// `_t` / `_forum_session` between requests, and the WKWebView cookie store
    /// can be ahead of the shared Rust cookie jar for a short window. Before
    /// nuking the session and presenting the login WebView, try a single host
    /// cookie resync per session epoch — if that resync actually replaces the
    /// auth cookies, the read can be retried in place.
    ///
    /// - Parameters:
    ///   - operation: human-readable name of the originating call site, used
    ///     for diagnostic breadcrumbs only.
    ///   - error: the error that was caught. Only `FireUniFfiError.LoginRequired`
    ///     attempts recovery; everything else returns `false` immediately.
    /// - Returns: `true` if a host cookie resync rotated the shared session
    ///   into a new auth epoch. The caller should retry the original read
    ///   exactly once. `false` means there is nothing more we can do at this
    ///   layer; the caller should fall back to
    ///   `handleRecoverableSessionErrorIfNeeded` to reset and present login.
    @discardableResult
    func attemptReadPathLoginRecovery(
        operation: String,
        error: Error
    ) async -> Bool {
        guard case FireUniFfiError.LoginRequired = error else {
            return false
        }

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

    private func handleAppStateRefreshEvent(_ event: AppStateRefreshEventState) {
        _ = event
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
