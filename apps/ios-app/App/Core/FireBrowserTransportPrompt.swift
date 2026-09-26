import Foundation

enum FireBrowserTransportPrompt {
    static func shouldPresent(
        kind: AuthRuntimeSignalKindState?,
        alreadyLatched: Bool
    ) -> Bool {
        kind == .askEnableBrowserTransport && !alreadyLatched
    }

    static func nextLatch(kind: AuthRuntimeSignalKindState?) -> Bool {
        kind == .askEnableBrowserTransport
    }
}
