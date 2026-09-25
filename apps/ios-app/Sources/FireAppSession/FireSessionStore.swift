import Foundation

public actor FireSessionStore {
    nonisolated let core: FireAppCore
    let baseURL: URL
    let workspacePath: String
    let sessionFilePath: String
    let authCookieStore: any FireAuthCookieSecureStore
    var authenticatedWriteHostResyncProvider: AuthenticatedWriteHostResyncProvider?
    var authenticatedWriteHostResyncTasks: [UInt64: Task<Void, Never>] = [:]
    var authenticatedWriteHostResyncAttemptedEpochs: Set<UInt64> = []
    var lastPersistedSnapshotRevision: UInt64
    var lastPersistedAuthCookieRevision: UInt64
    // Keep blocking diagnostics IO off elevated Swift concurrency executors.
    let diagnosticsQueue = DispatchQueue(
        label: "com.fire.session-store.diagnostics",
        qos: .utility
    )

    public init(
        baseURL: String? = nil,
        workspacePath: String? = nil,
        sessionFilePath: String? = nil,
        fileManager: FileManager = .default,
        authCookieStore: (any FireAuthCookieSecureStore)? = nil
    ) throws {
        let resolvedWorkspacePath = try workspacePath
            ?? sessionFilePath.map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            }
            ?? Self.defaultWorkspacePath(fileManager: fileManager)
        let core = try FireAppCore(baseUrl: baseURL, workspacePath: resolvedWorkspacePath)
        let resolvedBaseURL = URL(string: try core.session().snapshot().bootstrap.baseUrl)
            ?? URL(string: "https://linux.do")!
        let resolvedSessionFilePath = try sessionFilePath
            ?? core.session().resolveWorkspacePath(relativePath: "session.json")
        self.core = core
        self.baseURL = resolvedBaseURL
        self.workspacePath = resolvedWorkspacePath
        self.sessionFilePath = resolvedSessionFilePath
        self.authCookieStore = authCookieStore ?? FireKeychainAuthCookieStore(baseURL: resolvedBaseURL)
        let persistenceState = try core.session().sessionPersistenceState()
        self.lastPersistedSnapshotRevision = persistenceState.snapshotRevision
        self.lastPersistedAuthCookieRevision = persistenceState.authCookieRevision
    }

    public func snapshot() throws -> SessionState {
        try core.session().snapshot()
    }

    public func workspacePathValue() -> String {
        workspacePath
    }

    public nonisolated func logHost(level: HostLogLevelState, target: String, message: String) {
        try? core.diagnostics().logHost(level: level, target: target, message: message)
    }

    public nonisolated func makeLogger(target: String) -> FireHostLogger {
        let core = self.core
        return FireHostLogger(target: target) { level, target, message in
            try? core.diagnostics().logHost(level: level, target: target, message: message)
        }
    }
}
