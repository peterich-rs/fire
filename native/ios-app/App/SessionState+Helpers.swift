import Foundation

extension SessionState {
    static func placeholder(baseUrl: String = "https://linux.do") -> SessionState {
        SessionState(
            cookies: CookieState(),
            bootstrap: BootstrapState(baseUrl: baseUrl),
            readiness: SessionReadinessState(),
            loginPhase: .anonymous,
            hasLoginSession: false
        )
    }
}

extension LoginPhaseState {
    var title: String {
        switch self {
        case .anonymous:
            return "Anonymous"
        case .cookiesCaptured:
            return "Cookies Captured"
        case .bootstrapCaptured:
            return "Bootstrap Captured"
        case .ready:
            return "Ready"
        }
    }
}
