import UIKit

/// Central entry for in-app feedback (profile, shake, onboarding).
/// Does not require login. Auto-submit to GitHub is not wired yet — share / open issues.
///
/// Presentation is always a **full-screen independent page** (same secondary stack as
/// bookmarks / settings), never a half-height sheet panel.
@MainActor
enum FireFeedbackPresenter {
    static let issuesURL = URL(string: "https://github.com/peterich-rs/fire/issues")!
    static let newIssueBaseURL = URL(string: "https://github.com/peterich-rs/fire/issues/new")!
    static let shakeEnabledStorageKey = "fire.feedback.shakeEnabled"

    private static var lastPresentationAt: Date?
    private static let presentationCooldown: TimeInterval = 1.2
    private static weak var activeFeedback: FireFeedbackViewController?

    static var isShakeEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: shakeEnabledStorageKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: shakeEnabledStorageKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: shakeEnabledStorageKey)
        }
    }

    static var isFeedbackVisible: Bool {
        activeFeedback != nil
    }

    /// Present feedback as a full-screen page (profile / explicit buttons, no cooldown).
    static func present(
        from presenter: UIViewController? = nil,
        appViewModel: FireAppViewModel,
        source: String
    ) {
        presentInternal(
            from: presenter,
            appViewModel: appViewModel,
            source: source,
            respectCooldown: false
        )
    }

    /// Shake / accidental gestures: cooldown + ignore if already open.
    static func presentFromShake(appViewModel: FireAppViewModel) {
        guard isShakeEnabled else { return }
        presentInternal(
            from: nil,
            appViewModel: appViewModel,
            source: "shake",
            respectCooldown: true
        )
    }

    private static func presentInternal(
        from presenter: UIViewController?,
        appViewModel: FireAppViewModel,
        source: String,
        respectCooldown: Bool
    ) {
        if isFeedbackVisible {
            return
        }
        if respectCooldown, let last = lastPresentationAt,
           Date().timeIntervalSince(last) < presentationCooldown {
            return
        }
        lastPresentationAt = Date()

        let feedback = FireFeedbackViewController(viewModel: appViewModel, source: source)
        activeFeedback = feedback

        // Prefer the app-root secondary stack (full screen, covers tab bar) — same
        // path as bookmarks / settings / other profile drill-downs.
        if FireRootCoordinator.canPresentSecondary {
            FireRootCoordinator.presentSecondary(feedback)
            return
        }

        // Pre-tab shell (onboarding / early launch): full-screen modal page.
        let nav = UINavigationController(rootViewController: feedback)
        nav.modalPresentationStyle = .fullScreen
        guard let host = presenter ?? topViewController() else {
            activeFeedback = nil
            return
        }
        host.present(nav, animated: true)
    }

    static func feedbackDidDismiss() {
        activeFeedback = nil
    }

    private static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let base = base ?? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }()
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
