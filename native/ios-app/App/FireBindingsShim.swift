#if FIRE_USE_UNIFFI_STUBS
import Foundation

public enum LoginPhaseState: String, Codable, Sendable {
    case anonymous
    case cookiesCaptured
    case bootstrapCaptured
    case ready
}

public struct PlatformCookieState: Codable, Hashable, Sendable {
    public var name: String
    public var value: String
    public var domain: String?
    public var path: String?

    public init(name: String, value: String, domain: String?, path: String?) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
    }
}

public struct CookieState: Codable, Sendable {
    public var tToken: String?
    public var forumSession: String?
    public var cfClearance: String?
    public var csrfToken: String?

    public init(
        tToken: String? = nil,
        forumSession: String? = nil,
        cfClearance: String? = nil,
        csrfToken: String? = nil
    ) {
        self.tToken = tToken
        self.forumSession = forumSession
        self.cfClearance = cfClearance
        self.csrfToken = csrfToken
    }
}

public struct BootstrapState: Codable, Sendable {
    public var baseUrl: String
    public var discourseBaseUri: String?
    public var sharedSessionKey: String?
    public var currentUsername: String?
    public var longPollingBaseUrl: String?
    public var turnstileSitekey: String?
    public var topicTrackingStateMeta: String?
    public var preloadedJson: String?
    public var hasPreloadedData: Bool

    public init(
        baseUrl: String,
        discourseBaseUri: String? = nil,
        sharedSessionKey: String? = nil,
        currentUsername: String? = nil,
        longPollingBaseUrl: String? = nil,
        turnstileSitekey: String? = nil,
        topicTrackingStateMeta: String? = nil,
        preloadedJson: String? = nil,
        hasPreloadedData: Bool = false
    ) {
        self.baseUrl = baseUrl
        self.discourseBaseUri = discourseBaseUri
        self.sharedSessionKey = sharedSessionKey
        self.currentUsername = currentUsername
        self.longPollingBaseUrl = longPollingBaseUrl
        self.turnstileSitekey = turnstileSitekey
        self.topicTrackingStateMeta = topicTrackingStateMeta
        self.preloadedJson = preloadedJson
        self.hasPreloadedData = hasPreloadedData
    }
}

public struct SessionReadinessState: Codable, Sendable {
    public var hasLoginCookie: Bool
    public var hasForumSession: Bool
    public var hasCloudflareClearance: Bool
    public var hasCsrfToken: Bool
    public var hasCurrentUser: Bool
    public var hasPreloadedData: Bool
    public var hasSharedSessionKey: Bool
    public var canReadAuthenticatedApi: Bool
    public var canWriteAuthenticatedApi: Bool
    public var canOpenMessageBus: Bool

    public init(
        hasLoginCookie: Bool = false,
        hasForumSession: Bool = false,
        hasCloudflareClearance: Bool = false,
        hasCsrfToken: Bool = false,
        hasCurrentUser: Bool = false,
        hasPreloadedData: Bool = false,
        hasSharedSessionKey: Bool = false,
        canReadAuthenticatedApi: Bool = false,
        canWriteAuthenticatedApi: Bool = false,
        canOpenMessageBus: Bool = false
    ) {
        self.hasLoginCookie = hasLoginCookie
        self.hasForumSession = hasForumSession
        self.hasCloudflareClearance = hasCloudflareClearance
        self.hasCsrfToken = hasCsrfToken
        self.hasCurrentUser = hasCurrentUser
        self.hasPreloadedData = hasPreloadedData
        self.hasSharedSessionKey = hasSharedSessionKey
        self.canReadAuthenticatedApi = canReadAuthenticatedApi
        self.canWriteAuthenticatedApi = canWriteAuthenticatedApi
        self.canOpenMessageBus = canOpenMessageBus
    }
}

public struct SessionState: Codable, Sendable {
    public var cookies: CookieState
    public var bootstrap: BootstrapState
    public var readiness: SessionReadinessState
    public var loginPhase: LoginPhaseState
    public var hasLoginSession: Bool

    public init(
        cookies: CookieState,
        bootstrap: BootstrapState,
        readiness: SessionReadinessState,
        loginPhase: LoginPhaseState,
        hasLoginSession: Bool
    ) {
        self.cookies = cookies
        self.bootstrap = bootstrap
        self.readiness = readiness
        self.loginPhase = loginPhase
        self.hasLoginSession = hasLoginSession
    }
}

public struct LoginSyncState: Sendable {
    public var currentUrl: String?
    public var username: String?
    public var csrfToken: String?
    public var homeHtml: String?
    public var cookies: [PlatformCookieState]

    public init(
        currentUrl: String?,
        username: String?,
        csrfToken: String?,
        homeHtml: String?,
        cookies: [PlatformCookieState]
    ) {
        self.currentUrl = currentUrl
        self.username = username
        self.csrfToken = csrfToken
        self.homeHtml = homeHtml
        self.cookies = cookies
    }
}

public final class FireCoreHandle {
    private let storedBaseUrl: String
    private let storedWorkspacePath: String?
    private var state: SessionState

    public init(baseUrl: String?, workspacePath: String?) throws {
        let resolvedBaseUrl = baseUrl ?? "https://linux.do"
        self.storedBaseUrl = resolvedBaseUrl
        self.storedWorkspacePath = workspacePath
        self.state = SessionState.placeholder(baseUrl: resolvedBaseUrl)
    }

    public func baseUrl() -> String {
        storedBaseUrl
    }

    public func workspacePath() -> String? {
        storedWorkspacePath
    }

    public func resolveWorkspacePath(relativePath: String) throws -> String {
        guard let storedWorkspacePath, !storedWorkspacePath.isEmpty else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let nsRelativePath = relativePath as NSString
        let normalizedComponents = nsRelativePath.pathComponents.filter { $0 != "." }
        if nsRelativePath.isAbsolutePath
            || relativePath.isEmpty
            || normalizedComponents.contains("..")
        {
            throw CocoaError(.fileReadInvalidFileName)
        }

        return URL(fileURLWithPath: storedWorkspacePath)
            .appendingPathComponent(relativePath, isDirectory: false)
            .path
    }

    public func flushLogs(sync: Bool) {}

    public func hasLoginSession() -> Bool {
        state.hasLoginSession
    }

    public func snapshot() -> SessionState {
        state
    }

    public func syncLoginContext(context: LoginSyncState) throws -> SessionState {
        mergeCookies(context.cookies)
        state.cookies.csrfToken = context.csrfToken ?? state.cookies.csrfToken
        state.bootstrap.currentUsername = context.username ?? state.bootstrap.currentUsername
        if let homeHtml = context.homeHtml, !homeHtml.isEmpty {
            state.bootstrap.preloadedJson = homeHtml
            state.bootstrap.hasPreloadedData = true
        }
        updateDerivedState()
        return state
    }

    public func refreshBootstrap() throws -> SessionState {
        state.bootstrap.hasPreloadedData = true
        if state.bootstrap.currentUsername == nil {
            state.bootstrap.currentUsername = "guest"
        }
        updateDerivedState()
        return state
    }

    public func refreshCsrfToken() throws -> SessionState {
        if state.cookies.csrfToken == nil {
            state.cookies.csrfToken = UUID().uuidString
        }
        updateDerivedState()
        return state
    }

    public func exportSessionJson() throws -> String {
        let data = try JSONEncoder().encode(state)
        return String(decoding: data, as: UTF8.self)
    }

    public func restoreSessionJson(json: String) throws -> SessionState {
        let data = Data(json.utf8)
        state = try JSONDecoder().decode(SessionState.self, from: data)
        updateDerivedState()
        return state
    }

    public func saveSessionToPath(path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try exportSessionJson().write(to: url, atomically: true, encoding: .utf8)
    }

    public func loadSessionFromPath(path: String) throws -> SessionState {
        let url = URL(fileURLWithPath: path)
        let payload = try String(contentsOf: url, encoding: .utf8)
        return try restoreSessionJson(json: payload)
    }

    public func clearSessionPath(path: String) throws {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func logoutRemote(preserveCfClearance: Bool) throws -> SessionState {
        let clearance = preserveCfClearance ? state.cookies.cfClearance : nil
        state = SessionState.placeholder(baseUrl: storedBaseUrl)
        state.cookies.cfClearance = clearance
        updateDerivedState()
        return state
    }

    private func mergeCookies(_ cookies: [PlatformCookieState]) {
        for cookie in cookies {
            switch cookie.name {
            case "_t":
                state.cookies.tToken = cookie.value
            case "_forum_session":
                state.cookies.forumSession = cookie.value
            case "cf_clearance":
                state.cookies.cfClearance = cookie.value
            default:
                continue
            }
        }
    }

    private func updateDerivedState() {
        let hasLoginCookie = !(state.cookies.tToken?.isEmpty ?? true)
        let hasForumSession = !(state.cookies.forumSession?.isEmpty ?? true)
        let hasCsrfToken = !(state.cookies.csrfToken?.isEmpty ?? true)
        let hasCurrentUser = !(state.bootstrap.currentUsername?.isEmpty ?? true)
        let hasSharedSessionKey = !(state.bootstrap.sharedSessionKey?.isEmpty ?? true)
        let canReadAuthenticatedApi = hasLoginCookie && hasForumSession
        let canWriteAuthenticatedApi = canReadAuthenticatedApi && hasCsrfToken
        let canOpenMessageBus = canReadAuthenticatedApi && hasSharedSessionKey

        state.readiness = SessionReadinessState(
            hasLoginCookie: hasLoginCookie,
            hasForumSession: hasForumSession,
            hasCloudflareClearance: !(state.cookies.cfClearance?.isEmpty ?? true),
            hasCsrfToken: hasCsrfToken,
            hasCurrentUser: hasCurrentUser,
            hasPreloadedData: state.bootstrap.hasPreloadedData,
            hasSharedSessionKey: hasSharedSessionKey,
            canReadAuthenticatedApi: canReadAuthenticatedApi,
            canWriteAuthenticatedApi: canWriteAuthenticatedApi,
            canOpenMessageBus: canOpenMessageBus
        )
        state.hasLoginSession = hasLoginCookie
        state.loginPhase = {
            if !hasLoginCookie { return .anonymous }
            if !canReadAuthenticatedApi || !hasCurrentUser { return .cookiesCaptured }
            if !canWriteAuthenticatedApi || !state.bootstrap.hasPreloadedData { return .bootstrapCaptured }
            return .ready
        }()
    }
}
#endif
