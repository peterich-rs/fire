import Foundation

extension FireOnboardingViewController {
    func logAuth(_ message: String) {
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: message
        )
    }
}
