import AppIntents

struct FireSearchTopicsIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Topics"
    static var description = IntentDescription("Search topics in Fire.")
    static var openAppWhenRun = true

    @Parameter(title: "Search Query")
    var query: String?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        FireNavigationState.shared.pendingRoute = .search(query: query)
        return .result()
    }
}
