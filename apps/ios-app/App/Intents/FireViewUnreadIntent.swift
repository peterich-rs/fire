import AppIntents

struct FireViewUnreadIntent: AppIntent {
    static var title: LocalizedStringResource = "View Unread Notifications"
    static var description = IntentDescription("Open Fire's unread notification list.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        FireNavigationState.shared.pendingRoute = .notifications
        return .result()
    }
}
