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
}
