import Foundation

/// Why the onboarding/login host is being shown.
enum FireOnboardingEntry: Equatable, Sendable {
    /// App process launch — run startup validation and maybe auto-login.
    case coldStart
    /// User explicitly signed out (or host forced login UI) — show credential form only.
    case signedOut
    /// Authenticated session was invalidated mid-use (passive logout / login-required).
    /// Headless-capable methods may auto-login; explicit logout never uses this entry.
    case sessionExpired
}

/// Pure eligibility + routing helper for automatic login.
///
/// Cold-start: password + remembered credential, plus headless external OAuth
/// (Google first; pool grows after validation).
/// Mid-session / session-expired: headless external only so the original request
/// path can resume under a loading surface without a captcha detour.
enum FireAutoLoginKind: Equatable, Sendable {
    case password(FireSavedCredential)
    case external(FireExternalLoginMethod)
}

enum FireAutoLoginPlanner: Sendable {
    /// External providers eligible for headless auto-login.
    /// Add entries here after a provider is validated in production.
    static let headlessExternalPool: [FireLastLoginMethod: FireExternalLoginMethod] = [
        .google: .google,
        // .github: .github,
        // .x: .x,
        // .discord: .discord,
        // .apple: .apple,
    ]

    /// Returns the auto-login path for the given onboarding entry, if any.
    /// Explicit logout must never re-trigger auto-login.
    static func autoLoginKind(
        entry: FireOnboardingEntry,
        lastLoginMethod: FireLastLoginMethod?,
        savedCredential: FireSavedCredential?
    ) -> FireAutoLoginKind? {
        switch entry {
        case .signedOut:
            return nil
        case .coldStart:
            return coldStartKind(
                lastLoginMethod: lastLoginMethod,
                savedCredential: savedCredential
            )
        case .sessionExpired:
            return midSessionHeadlessKind(lastLoginMethod: lastLoginMethod).map(FireAutoLoginKind.external)
        }
    }

    /// Back-compat wrapper used by existing cold-start call sites and tests.
    static func coldStartKind(
        entry: FireOnboardingEntry,
        lastLoginMethod: FireLastLoginMethod?,
        savedCredential: FireSavedCredential?
    ) -> FireAutoLoginKind? {
        autoLoginKind(
            entry: entry,
            lastLoginMethod: lastLoginMethod,
            savedCredential: savedCredential
        )
    }

    /// Headless external method eligible for mid-session reauth while the main shell stays up.
    static func midSessionHeadlessKind(
        lastLoginMethod: FireLastLoginMethod?
    ) -> FireExternalLoginMethod? {
        guard let lastLoginMethod else { return nil }
        return headlessExternalPool[lastLoginMethod]
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

    private static func coldStartKind(
        lastLoginMethod: FireLastLoginMethod?,
        savedCredential: FireSavedCredential?
    ) -> FireAutoLoginKind? {
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
}
