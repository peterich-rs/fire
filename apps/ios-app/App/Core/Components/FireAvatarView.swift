import SwiftUI
import UIKit

private let fireAvatarPlaceholderOpacity = 0.6
private let fireAvatarCanonicalPixelSize = 384


func fireAvatarURL(
    avatarTemplate: String?,
    size: CGFloat,
    scale: CGFloat,
    baseURLString: String = "https://linux.do"
) -> URL? {
    guard let avatarTemplate, !avatarTemplate.isEmpty else {
        return nil
    }

    let displayPixelSize = max(1, Int((size * scale).rounded(.up)))
    let pixelSize = max(displayPixelSize, fireAvatarCanonicalPixelSize)
    let path = avatarTemplate.replacingOccurrences(of: "{size}", with: "\(pixelSize)")
    if path.hasPrefix("http") {
        return URL(string: path)
    }
    if path.hasPrefix("//") {
        let scheme = URL(string: baseURLString)?.scheme ?? "https"
        return URL(string: "\(scheme):\(path)")
    }
    return URL(string: path, relativeTo: URL(string: baseURLString))?.absoluteURL
}

struct FireAvatarView: View {
    let avatarTemplate: String?
    let username: String
    let size: CGFloat
    var baseURLString: String = "https://linux.do"

    private var avatarRequest: FireAvatarImageRequest? {
        guard let avatarURL = fireAvatarURL(
            avatarTemplate: avatarTemplate,
            size: size,
            scale: UIScreen.main.scale,
            baseURLString: baseURLString
        ) else {
            return nil
        }
        return FireAvatarImageRequest(url: avatarURL)
    }

    private var monogram: String {
        monogramForUsername(username: username.isEmpty ? "?" : username)
    }

    var body: some View {
        FireRemoteImage(request: avatarRequest) { resolvedImage in
            Image(uiImage: resolvedImage)
                .resizable()
                .scaledToFill()
        } placeholder: { state in
            monogramView
                .opacity(state == .loading && avatarRequest != nil ? fireAvatarPlaceholderOpacity : 1)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var monogramView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [FireTheme.accent, FireTheme.accentSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(monogram)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
