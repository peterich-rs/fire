import SwiftUI

@main
struct FireApp: App {
    @UIApplicationDelegateAdaptor(FireAppDelegate.self) private var appDelegate
    @StateObject private var navigationState = FireNavigationState.shared

    var body: some Scene {
        WindowGroup {
            FireTabRoot()
                .environmentObject(navigationState)
                .onOpenURL { url in
                    guard let route = FireRouteParser.parse(url: url) else {
                        return
                    }
                    navigationState.pendingRoute = route
                }
        }
    }
}
