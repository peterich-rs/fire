import Foundation

extension FireSessionStore {
    public func completeReadPathLogin(generation: UInt64, succeeded: Bool) throws {
        try core.session().completeReadPathLogin(generation: generation, succeeded: succeeded)
    }

    /// Topic-detail session open/cancel/close only touch UniFFI/`core` and must stay
    /// callable from `@MainActor` hosts without hopping onto the session actor.
    public func restorePersistedSessionIfAvailable() throws -> SessionState? {
        guard FileManager.default.fileExists(atPath: sessionFilePath) else {
            return nil
        }
        let state = try core.session().loadSessionFromPath(path: sessionFilePath)
        let persistenceState = try currentSessionPersistenceState()
        lastPersistedSnapshotRevision = persistenceState.snapshotRevision
        return state
    }

    @discardableResult
    public func prepareStartupSession() async throws -> SessionState {
        try await restoreColdStartSession()
    }

    @discardableResult
    public func restoreColdStartSession() async throws -> SessionState {
        try await restoreColdStartSession(
            refreshBootstrapIfNeeded: {
                try await self.refreshBootstrapIfNeeded()
            },
            refreshBootstrapDuringRestore: false
        )
    }

    @discardableResult
    func restoreColdStartSession(
        refreshBootstrapIfNeeded: () async throws -> SessionState,
        refreshBootstrapDuringRestore: Bool = false
    ) async throws -> SessionState {
        _ = try restorePersistedSessionIfAvailable()
        let secureSecrets = try authCookieStore.load()

        if !secureSecrets.isEmpty {
            _ = try applyPlatformCookies(secureSecrets.platformCookies(baseURL: baseURL))
        }

        let current = try core.session().snapshot()
        if !current.readiness.canReadAuthenticatedApi && shouldDiscardRestoredBootstrap(current) {
            logHost(
                level: .warn,
                target: "session.cold_start",
                message: "Cold-start session has valid user bootstrap but platform cookies are missing/expired. Preserving session to allow recovery."
            )
        }

        guard refreshBootstrapDuringRestore else {
            return current
        }

        return try await refreshBootstrapIfNeeded()
    }

    public func persistCurrentSession() throws {
        try persistCurrentSession(force: true)
    }

    func persistCurrentSessionIfNeeded() throws {
        try persistCurrentSession(force: false)
    }

    private func persistCurrentSession(force: Bool) throws {
        let persistenceState = try currentSessionPersistenceState()
        try persistCurrentAuthCookies(persistenceState: persistenceState, force: force)
        try persistSessionFile(persistenceState: persistenceState, force: force)
    }

    public func exportSessionJSON() throws -> String {
        try core.session().exportSessionJson()
    }

    public func clearPersistedSession() throws {
        try core.session().clearSessionPath(path: sessionFilePath)
        lastPersistedSnapshotRevision = 0
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
        try repairDiagnosticsDirectoryIfNeeded(
            workspaceDirectory: fireDirectory,
            fileManager: fileManager
        )
        return fireDirectory.path
    }

    private static func repairDiagnosticsDirectoryIfNeeded(
        workspaceDirectory: URL,
        fileManager: FileManager
    ) throws {
        let diagnosticsDirectory = workspaceDirectory.appendingPathComponent(
            "diagnostics",
            isDirectory: true
        )
        let diagnosticsPath = diagnosticsDirectory.path
        guard fileManager.fileExists(atPath: diagnosticsPath) else {
            return
        }
        guard fileManager.isWritableFile(atPath: diagnosticsPath) == false else {
            return
        }
        try fileManager.removeItem(at: diagnosticsDirectory)
        try fileManager.createDirectory(
            at: diagnosticsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    public static func defaultSessionFilePath(fileManager: FileManager = .default) throws -> String {
        let workspacePath = try defaultWorkspacePath(fileManager: fileManager)
        return URL(fileURLWithPath: workspacePath)
            .appendingPathComponent("session.json", isDirectory: false)
            .path
    }

    private func shouldDiscardRestoredBootstrap(_ session: SessionState) -> Bool {
        session.readiness.hasCurrentUser
            || session.readiness.hasPreloadedData
            || session.readiness.hasSharedSessionKey
    }

    func currentSessionPersistenceState() throws -> SessionPersistenceState {
        try core.session().sessionPersistenceState()
    }

    private func persistCurrentAuthCookies(
        persistenceState: SessionPersistenceState,
        force: Bool
    ) throws {
        guard force || persistenceState.authCookieRevision != lastPersistedAuthCookieRevision else {
            return
        }

        try authCookieStore.save(FireAuthCookieSecrets(cookieState: try core.session().snapshot().cookies))
        lastPersistedAuthCookieRevision = persistenceState.authCookieRevision
    }

    private func persistSessionFile(
        persistenceState: SessionPersistenceState,
        force: Bool
    ) throws {
        guard force || persistenceState.snapshotRevision != lastPersistedSnapshotRevision else {
            return
        }

        try core.session().saveSessionToPath(path: sessionFilePath)
        lastPersistedSnapshotRevision = persistenceState.snapshotRevision
    }

    public func currentSessionEpoch() throws -> UInt64 {
        try core.session().sessionEpoch()
    }

    @discardableResult
    public func restoreSessionJSON(_ json: String) throws -> SessionState {
        let state = try core.session().restoreSessionJson(json: json)
        try persistCurrentSessionIfNeeded()
        return state
    }

    // MARK: - MessageBus
}
