import UIKit

/// Official linux.do external login entries shown on the native credential form.
/// OAuth providers match runtime `auth_providers`; passkey is the Discourse first-factor button.
enum FireExternalLoginMethod: String, CaseIterable, Sendable {
    case google
    case github
    case x
    case discord
    case apple
    case passkey

    /// Maps a persisted last-login value onto the third-party icon row.
    /// Password login is a first-class `FireLastLoginMethod`, but it is not an
    /// external-provider icon, so this conversion is optional by design.
    static func externalIcon(for lastLoginMethod: FireLastLoginMethod) -> FireExternalLoginMethod? {
        switch lastLoginMethod {
        case .password:
            return nil
        case .google:
            return .google
        case .github:
            return .github
        case .x:
            return .x
        case .discord:
            return .discord
        case .apple:
            return .apple
        case .passkey:
            return .passkey
        }
    }

    var lastLoginMethod: FireLastLoginMethod {
        switch self {
        case .google: return .google
        case .github: return .github
        case .x: return .x
        case .discord: return .discord
        case .apple: return .apple
        case .passkey: return .passkey
        }
    }

    /// Discourse `button.btn-social.{name}` class / `/auth/{name}` provider key.
    /// `nil` for passkey, which uses `button.passkey-login-button`.
    var discourseProviderName: String? {
        switch self {
        case .google: return "google_oauth2"
        case .github: return "github"
        case .x: return "twitter"
        case .discord: return "discord"
        case .apple: return "apple"
        case .passkey: return nil
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .google: return "使用 Google 登录"
        case .github: return "使用 GitHub 登录"
        case .x: return "使用 X 登录"
        case .discord: return "使用 Discord 登录"
        case .apple: return "使用 Apple 登录"
        case .passkey: return "使用通行密钥登录"
        }
    }

    /// Asset catalog name for the official brand / passkey glyph.
    var assetName: String {
        switch self {
        case .google: return "LoginProviderGoogle"
        case .github: return "LoginProviderGitHub"
        case .x: return "LoginProviderX"
        case .discord: return "LoginProviderDiscord"
        case .apple: return "LoginProviderApple"
        case .passkey: return "LoginProviderPasskey"
        }
    }

    var iconImage: UIImage {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        guard let image = UIImage(named: assetName) else {
            // Defensive fallback if an asset is missing from the catalog.
            return UIImage(systemName: "questionmark.circle", withConfiguration: symbolConfig)
                ?? UIImage()
        }
        // Asset catalog already provides light/dark monochrome variants and
        // multicolor brand art. Keep original rendering so dark-mode whites
        // are not re-tinted into unreadable blobs.
        return image
            .resizedToPointSize(CGSize(width: 24, height: 24))
            .withRenderingMode(.alwaysOriginal)
    }
}

private extension UIImage {
    func resizedToPointSize(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = UITraitCollection.current.displayScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
