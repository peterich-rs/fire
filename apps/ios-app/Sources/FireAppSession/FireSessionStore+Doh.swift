import Foundation

extension FireSessionStore {
    public func listDohPresets() throws -> [DohPresetState] {
        try core.session().listDohPresets()
    }

    public func getDohSettings() throws -> DohSettingsState {
        try core.session().getDohSettings()
    }

    @discardableResult
    public func setDohSettings(_ settings: DohSettingsState) throws -> DohSettingsState {
        try core.session().setDohSettings(settings: settings)
    }

    public func probeDohSettings(
        _ settings: DohSettingsState,
        host: String? = nil
    ) async throws -> DohProbeResultState {
        try await core.session().probeDohSettings(settings: settings, host: host)
    }

    public func getCloudflarePolicy() throws -> CloudflarePolicyState {
        try core.session().getCloudflarePolicy()
    }

    @discardableResult
    public func setCloudflarePolicy(_ policy: CloudflarePolicyState) throws -> CloudflarePolicyState {
        try core.session().setCloudflarePolicy(policy: policy)
    }

    public func enableBrowserTransportForSession() throws {
        try core.session().enableBrowserTransportForSession()
    }

    public func declineBrowserTransport() throws {
        try core.session().declineBrowserTransport()
    }

    public func noteAppBackgrounded() throws {
        try core.session().noteAppBackgrounded()
    }

    public func noteAppForegrounded() throws {
        try core.session().noteAppForegrounded()
    }

    public func registerBrowserHttpHandler(_ handler: any BrowserHttpHandler) throws {
        try core.session().registerBrowserHttpHandler(handler: handler)
    }
}
