import Foundation

extension FireSessionStore {
    public func ensurePreloadedDataLoaded() async throws {
        try await core.session().ensurePreloadedDataLoaded()
        try persistCurrentSessionIfNeeded()
    }

    public func awaitPreloadedData() async throws -> PreloadedDataStateState {
        let state = try await core.session().awaitPreloadedData()
        try persistCurrentSessionIfNeeded()
        return state
    }

    public func currentUserDefaults() -> CurrentUserSnapshotState? {
        try? core.session().currentUserSnapshot()
    }

    public func cachedUser() -> CurrentUserSnapshotState? {
        try? core.session().cachedUser()
    }

    public func triggerAppStateRefresh(_ trigger: RefreshTriggerState) async throws {
        try await core.session().triggerAppStateRefresh(trigger: trigger)
        try persistCurrentSessionIfNeeded()
    }

    public func triggerAppStateRefresh(
        _ trigger: RefreshTriggerState,
        handler: any AppStateRefreshHandler
    ) async throws {
        try await core.session().triggerAppStateRefreshWithHandler(
            trigger: trigger,
            handler: handler
        )
        try persistCurrentSessionIfNeeded()
    }

    @discardableResult
    public func refreshBootstrapIfNeeded() async throws -> SessionState {
        let refreshed = try await core.session().refreshBootstrapIfNeeded()
        try persistCurrentSessionIfNeeded()
        return refreshed
    }

    @discardableResult
    public func refreshCsrfTokenIfNeeded() async throws -> SessionState {
        let refreshed = try await core.session().refreshCsrfTokenIfNeeded()
        try persistCurrentSessionIfNeeded()
        return refreshed
    }

    @discardableResult
    public func refreshBootstrap() async throws -> SessionState {
        let refreshed = try await core.session().refreshBootstrap()
        try persistCurrentSessionIfNeeded()
        return refreshed
    }
}
