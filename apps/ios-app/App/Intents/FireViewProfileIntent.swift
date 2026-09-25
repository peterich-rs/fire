import AppIntents

struct FireViewProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "View Profile"
    static var description = IntentDescription("Open your Fire profile.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        FireNavigationState.shared.pendingRoute = .profileTab
        return .result()
    }
}
