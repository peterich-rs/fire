import AppIntents

struct FireShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FireViewUnreadIntent(),
            phrases: [
                "View unread in \(.applicationName)",
                "Open \(.applicationName) notifications"
            ],
            shortTitle: "Unread",
            systemImageName: "bell.badge"
        )
        AppShortcut(
            intent: FireSearchTopicsIntent(),
            phrases: [
                "Search in \(.applicationName)",
                "Search topics in \(.applicationName)"
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: FireViewProfileIntent(),
            phrases: [
                "View profile in \(.applicationName)",
                "Open \(.applicationName) profile"
            ],
            shortTitle: "Profile",
            systemImageName: "person.circle"
        )
    }
}
