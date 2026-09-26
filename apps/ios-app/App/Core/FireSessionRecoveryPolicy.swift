import Foundation

enum FireSessionRecoveryPolicy {
    /// Cloudflare recovery owns the epoch. A readiness flicker must not clear
    /// identity cookies, start Google reauth, or stack a browser-transport alert.
    static func suppressesHostLoginRecovery(_ recovery: SessionRecoveryState) -> Bool {
        recovery == .cloudflare
    }
}
