import Foundation

extension FireSessionStore {
    typealias AuthenticatedWriteHostResyncProvider = @MainActor @Sendable () async throws -> [PlatformCookieState]?

    struct AuthenticatedWritePreflightContext: Sendable {
        let sessionEpoch: UInt64
        let authRecoveryHint: AuthRecoveryHintState?
    }

    func setAuthenticatedWriteHostResyncProvider(
        _ provider: AuthenticatedWriteHostResyncProvider?
    ) {
        authenticatedWriteHostResyncProvider = provider
    }

    private func authenticatedWritePreflightContext() throws -> AuthenticatedWritePreflightContext {
        AuthenticatedWritePreflightContext(
            sessionEpoch: try core.session().sessionEpoch(),
            authRecoveryHint: try core.session().authRecoveryHint()
        )
    }

    /// Read-side helper: returns the current shared session epoch so callers can
    /// detect whether a host cookie resync actually replaced the auth cookies.
    private func refreshCsrfTokenForAuthenticatedWritePreflight() async throws -> AuthenticatedWritePreflightContext {
        _ = try await refreshCsrfTokenIfNeeded()
        return try authenticatedWritePreflightContext()
    }

    private func applyPlatformCookiesForAuthenticatedWritePreflight(
        _ cookies: [PlatformCookieState]
    ) async throws -> AuthenticatedWritePreflightContext {
        guard Self.containsActiveAuthCookies(in: cookies) else {
            logHost(
                level: .info,
                target: "session.auth_write_preflight",
                message: "Skipping authoritative platform cookie apply because host resync returned partial auth cookies."
            )
            return try authenticatedWritePreflightContext()
        }
        _ = try applyPlatformCookies(cookies)
        return try authenticatedWritePreflightContext()
    }

    nonisolated private static func containsActiveAuthCookies(
        in cookies: [PlatformCookieState]
    ) -> Bool {
        let activeCookies = cookies.filter { cookie in
            let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && !(cookie.expiresAtUnixMs.map { $0 <= currentUnixMs() } ?? false)
        }

        return activeCookies.contains(where: { $0.name == "_t" })
            && activeCookies.contains(where: { $0.name == "_forum_session" })
    }

    nonisolated private static func currentUnixMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func runAuthenticatedWritePreflight() async throws {
        try await runAuthenticatedWritePreflight(
            readContext: {
                try await self.authenticatedWritePreflightContext()
            },
            refreshCsrfTokenIfNeeded: {
                try await self.refreshCsrfTokenForAuthenticatedWritePreflight()
            },
            applyPlatformCookies: { cookies in
                try await self.applyPlatformCookiesForAuthenticatedWritePreflight(cookies)
            },
            hostResyncProvider: authenticatedWriteHostResyncProvider
        )
    }

    func runAuthenticatedWritePreflight(
        readContext: @escaping @Sendable () async throws -> AuthenticatedWritePreflightContext,
        refreshCsrfTokenIfNeeded: @escaping @Sendable () async throws -> AuthenticatedWritePreflightContext,
        applyPlatformCookies: @escaping @Sendable ([PlatformCookieState]) async throws -> AuthenticatedWritePreflightContext,
        hostResyncProvider: AuthenticatedWriteHostResyncProvider?
    ) async throws {
        let initialContext = try await readContext()
        let refreshedContext = try await refreshCsrfTokenIfNeeded()

        guard
            let recoveryHint = initialContext.authRecoveryHint,
            recoveryHint.observedEpoch == initialContext.sessionEpoch,
            refreshedContext.sessionEpoch == initialContext.sessionEpoch,
            let refreshedHint = refreshedContext.authRecoveryHint,
            refreshedHint.observedEpoch == initialContext.sessionEpoch
        else {
            return
        }

        guard let hostResyncProvider else {
            return
        }

        await runAuthenticatedWriteHostResyncIfNeeded(
            for: initialContext.sessionEpoch,
            readContext: readContext,
            applyPlatformCookies: applyPlatformCookies,
            hostResyncProvider: hostResyncProvider
        )
        _ = try await refreshCsrfTokenIfNeeded()
    }

    private func runAuthenticatedWriteHostResyncIfNeeded(
        for sessionEpoch: UInt64,
        readContext: @escaping @Sendable () async throws -> AuthenticatedWritePreflightContext,
        applyPlatformCookies: @escaping @Sendable ([PlatformCookieState]) async throws -> AuthenticatedWritePreflightContext,
        hostResyncProvider: @escaping AuthenticatedWriteHostResyncProvider
    ) async {
        if let existingTask = authenticatedWriteHostResyncTasks[sessionEpoch] {
            await existingTask.value
            return
        }

        guard !authenticatedWriteHostResyncAttemptedEpochs.contains(sessionEpoch) else {
            return
        }

        authenticatedWriteHostResyncAttemptedEpochs.insert(sessionEpoch)
        let task = Task<Void, Never> { [self] in
            do {
                try await executeAuthenticatedWriteHostResync(
                    for: sessionEpoch,
                    readContext: readContext,
                    applyPlatformCookies: applyPlatformCookies,
                    hostResyncProvider: hostResyncProvider
                )
            } catch {
            }
            clearAuthenticatedWriteHostResyncTask(for: sessionEpoch)
        }
        authenticatedWriteHostResyncTasks[sessionEpoch] = task
        await task.value
    }

    private func executeAuthenticatedWriteHostResync(
        for sessionEpoch: UInt64,
        readContext: @escaping @Sendable () async throws -> AuthenticatedWritePreflightContext,
        applyPlatformCookies: @escaping @Sendable ([PlatformCookieState]) async throws -> AuthenticatedWritePreflightContext,
        hostResyncProvider: @escaping AuthenticatedWriteHostResyncProvider
    ) async throws {
        let beforeProviderContext = try await readContext()
        guard
            beforeProviderContext.sessionEpoch == sessionEpoch,
            let recoveryHint = beforeProviderContext.authRecoveryHint,
            recoveryHint.observedEpoch == sessionEpoch
        else {
            return
        }

        guard let platformCookies = try await hostResyncProvider(), !platformCookies.isEmpty else {
            return
        }

        let beforeApplyContext = try await readContext()
        guard
            beforeApplyContext.sessionEpoch == sessionEpoch,
            let recoveryHint = beforeApplyContext.authRecoveryHint,
            recoveryHint.observedEpoch == sessionEpoch
        else {
            return
        }

        _ = try await applyPlatformCookies(platformCookies)
    }

    private func clearAuthenticatedWriteHostResyncTask(for sessionEpoch: UInt64) {
        authenticatedWriteHostResyncTasks.removeValue(forKey: sessionEpoch)
    }

    func runAuthenticatedWritePersistingSessionChanges<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        try await runAuthenticatedWritePreflight()
        return try await runPersistingSessionChanges(operation)
    }

    func runPersistingSessionChanges<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        let result = try await operation()
        try persistCurrentSessionIfNeeded()
        return result
    }
}
