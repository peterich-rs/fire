import SwiftUI

@main
struct FireApp: App {
    @UIApplicationDelegateAdaptor(FireAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            FireTabRoot()
        }
    }
}
