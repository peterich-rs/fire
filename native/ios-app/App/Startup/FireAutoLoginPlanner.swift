import Foundation

/// Why the onboarding/login host is being shown.
enum FireOnboardingEntry: Equatable, Sendable {
    /// App process launch — run startup validation and maybe auto-login.
    case coldStart
    /// User explicitly signed out (or host forced login UI) — show credential form only.
    case signedOut
}

/// Pure eligibility + routing helper for cold-start automatic login.
///
/// Phase 1: password + remembered credential.
/// Phase 2: headless external OAuth (Google first; pool grows after validation).
enum FireAutoLoginKind: Equatable, Sendable {
    case password(FireSavedCredential)
    case external(FireExternalLoginMethod)
}

enum FireAutoLoginPlanner: Sendable {
    /// External providers eligible for headless cold-start auto-login.
    /// Add entries here after a provider is validated in production.
    static let headlessExternalPool: [FireLastLoginMethod: FireExternalLoginMethod] = [
        .google: .google,
        // .github: .github,
        // .x: .x,
        // .discord: .discord,
        // .apple: .apple,
    ]

    /// Returns the auto-login path to attempt after startup auth validation fails.
    /// Auto-login is cold-start only — explicit logout must never re-trigger it.
    /// - Note: CF / runtime session recovery is intentionally out of scope here.
    static func coldStartKind(
        entry: FireOnboardingEntry,
        lastLoginMethod: FireLastLoginMethod?,
        savedCredential: FireSavedCredential?
    ) -> FireAutoLoginKind? {
        guard entry == .coldStart else { return nil }

        switch lastLoginMethod {
        case .password:
            guard let savedCredential else { return nil }
            return .password(savedCredential)
        case .google, .github, .x, .discord, .apple, .passkey:
            guard let method = lastLoginMethod,
                  let external = headlessExternalPool[method] else {
                return nil
            }
            return .external(external)
        case .none:
            return nil
        }
    }

    static func loadingMessage(for kind: FireAutoLoginKind) -> String {
        switch kind {
        case .password:
            return "正在准备安全验证…"
        case let .external(method):
            switch method {
            case .google:
                return "正在通过 Google 登录…"
            case .github:
                return "正在通过 GitHub 登录…"
            case .x:
                return "正在通过 X 登录…"
            case .discord:
                return "正在通过 Discord 登录…"
            case .apple:
                return "正在通过 Apple 登录…"
            case .passkey:
                return "正在通过通行密钥登录…"
            }
        }
    }

    static func captchaUnderlyingMessage(for kind: FireAutoLoginKind) -> String {
        switch kind {
        case .password:
            return "请完成安全验证"
        case .external:
            return loadingMessage(for: kind)
        }
    }

    static func supportsHeadlessExternal(_ method: FireLastLoginMethod) -> Bool {
        headlessExternalPool[method] != nil
    }
}
