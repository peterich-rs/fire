import Foundation

public enum FireSessionStoreError: Error {
    case missingApplicationSupportDirectory
}

public struct FireCapturedLoginState: Sendable {
    public let currentURL: String?
    public let username: String?
    public let csrfToken: String?
    public let homeHTML: String?
    public let cookies: [PlatformCookieState]

    public init(
        currentURL: String?,
        username: String?,
        csrfToken: String?,
        homeHTML: String?,
        cookies: [PlatformCookieState]
    ) {
        self.currentURL = currentURL
        self.username = username
        self.csrfToken = csrfToken
        self.homeHTML = homeHTML
        self.cookies = cookies
    }
}

public actor FireSessionStore {
    private let core: FireCoreHandle
    private let workspacePath: String
    private let sessionFilePath: String

    public init(
        baseURL: String? = nil,
        workspacePath: String? = nil,
        sessionFilePath: String? = nil,
        fileManager: FileManager = .default
    ) throws {
        let resolvedWorkspacePath = try workspacePath
            ?? sessionFilePath.map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            }
            ?? Self.defaultWorkspacePath(fileManager: fileManager)
        let core = try FireCoreHandle(baseUrl: baseURL, workspacePath: resolvedWorkspacePath)
        let resolvedSessionFilePath = try sessionFilePath
            ?? core.resolveWorkspacePath(relativePath: "session.json")
        self.core = core
        self.workspacePath = resolvedWorkspacePath
        self.sessionFilePath = resolvedSessionFilePath
    }

    public func snapshot() -> SessionState {
        core.snapshot()
    }

    public func restorePersistedSessionIfAvailable() throws -> SessionState? {
        guard FileManager.default.fileExists(atPath: sessionFilePath) else {
            return nil
        }
        return try core.loadSessionFromPath(path: sessionFilePath)
    }

    @discardableResult
    public func syncLoginContext(_ captured: FireCapturedLoginState) throws -> SessionState {
        let state = try core.syncLoginContext(
            context: LoginSyncState(
                currentUrl: captured.currentURL,
                username: captured.username,
                csrfToken: captured.csrfToken,
                homeHtml: captured.homeHTML,
                cookies: captured.cookies
            )
        )
        try persistCurrentSession()
        return state
    }

    @discardableResult
    public func refreshBootstrapIfNeeded() throws -> SessionState {
        let current = core.snapshot()
        if current.bootstrap.hasPreloadedData {
            return current
        }

        let refreshed = try core.refreshBootstrap()
        try persistCurrentSession()
        return refreshed
    }

    @discardableResult
    public func refreshCsrfTokenIfNeeded() throws -> SessionState {
        let current = core.snapshot()
        if current.cookies.csrfToken != nil {
            return current
        }

        let refreshed = try core.refreshCsrfToken()
        try persistCurrentSession()
        return refreshed
    }

    public func persistCurrentSession() throws {
        try core.saveSessionToPath(path: sessionFilePath)
    }

    public func workspacePathValue() -> String {
        workspacePath
    }

    public func exportSessionJSON() throws -> String {
        try core.exportSessionJson()
    }

    @discardableResult
    public func restoreSessionJSON(_ json: String) throws -> SessionState {
        let state = try core.restoreSessionJson(json: json)
        try persistCurrentSession()
        return state
    }

    @discardableResult
    public func logout() throws -> SessionState {
        let state = try core.logoutRemote(preserveCfClearance: true)
        try clearPersistedSession()
        return state
    }

    public func clearPersistedSession() throws {
        try core.clearSessionPath(path: sessionFilePath)
    }

    public static func defaultWorkspacePath(fileManager: FileManager = .default) throws -> String {
        guard let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) as URL? else {
            throw FireSessionStoreError.missingApplicationSupportDirectory
        }

        let fireDirectory = directory.appendingPathComponent("Fire", isDirectory: true)
        try fileManager.createDirectory(
            at: fireDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return fireDirectory.path
    }

    public static func defaultSessionFilePath(fileManager: FileManager = .default) throws -> String {
        let workspacePath = try defaultWorkspacePath(fileManager: fileManager)
        return URL(fileURLWithPath: workspacePath)
            .appendingPathComponent("session.json", isDirectory: false)
            .path
    }
}
