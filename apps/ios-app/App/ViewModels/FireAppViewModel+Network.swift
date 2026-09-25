import Foundation

extension FireAppViewModel {
    func listDohPresets() async throws -> [DohPresetState] {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.listDohPresets()
    }

    func getDohSettings() async throws -> DohSettingsState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.getDohSettings()
    }

    @discardableResult
    func setDohSettings(_ settings: DohSettingsState) async throws -> DohSettingsState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.setDohSettings(settings)
    }

    func probeDohSettings(
        _ settings: DohSettingsState,
        host: String? = nil
    ) async throws -> DohProbeResultState {
        let sessionStore = try await sessionStoreValue()
        return try await sessionStore.probeDohSettings(settings, host: host)
    }
}
