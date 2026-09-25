import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    func configureAvatar(payload: FirePostCellRenderPayload, avatarSize: CGFloat) {
        let username = payload.post.username.isEmpty ? "?" : payload.post.username
        let avatarURL = fireAvatarURL(
            avatarTemplate: payload.post.avatarTemplate,
            size: avatarSize,
            scale: cachedDisplayScale,
            baseURLString: payload.baseURLString
        )
        let nextAvatarSignature = [
            username,
            payload.post.avatarTemplate ?? "",
            payload.baseURLString,
            avatarURL?.absoluteString ?? "monogram",
            String(Int(avatarSize.rounded())),
        ].joined(separator: "\u{1F}")
        guard avatarSignature != nextAvatarSignature else {
            return
        }
        avatarSignature = nextAvatarSignature

        let monogram = monogramForUsername(username: username)
        avatarMonogramNode.attributedText = NSAttributedString(
            string: monogram,
            attributes: [
                .font: UIFont.systemFont(ofSize: avatarSize * 0.36, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
        )
        avatarMonogramNode.isHidden = false
        avatarNode.isHidden = true
        avatarNode.alpha = 0

        if let avatarURL {
            avatarNode.isHidden = false
            avatarNode.alpha = 0
            loadAvatar(url: avatarURL)
        } else {
            cancelAvatarLoad()
            avatarNode.isHidden = true
        }
    }

    func configureMeta(payload: FirePostCellRenderPayload) {
        let subheadlineFont = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold
            )
        )
        let captionFont = UIFont.preferredFont(forTextStyle: .caption2)
        let monoCaptionFont = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.monospacedDigitSystemFont(
                ofSize: captionFont.pointSize,
                weight: .regular
            )
        )

        let appearance = payload.appearance
        let primaryInk = appearance.ink
        let secondaryInk = appearance.subtleInk
        let tertiaryInk = appearance.tertiaryInk

        usernameNode.attributedText = NSAttributedString(
            string: FirePostAuthorMetadataDisplay.displayName(for: payload.post),
            attributes: [.font: subheadlineFont, .foregroundColor: primaryInk]
        )
        let canOpenProfile = !payload.post.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        avatarContainerNode.accessibilityLabel = canOpenProfile
            ? "查看 \(FirePostAuthorMetadataDisplay.displayName(for: payload.post)) 的资料"
            : "查看用户资料"

        let primaryBadges = FirePostAuthorMetadataDisplay.primaryBadgeParts(for: payload.post)
        if primaryBadges.isEmpty {
            authorBadgeNode.isHidden = true
            authorBadgeNode.attributedText = nil
        } else {
            authorBadgeNode.isHidden = false
            authorBadgeNode.attributedText = Self.badgeAttributedText(parts: primaryBadges)
        }

        let secondaryParts = FirePostAuthorMetadataDisplay.secondaryLineParts(for: payload.post)
        if secondaryParts.isEmpty {
            authorMetadataNode.isHidden = true
            authorMetadataNode.attributedText = nil
        } else {
            authorMetadataNode.isHidden = false
            authorMetadataNode.attributedText = NSAttributedString(
                string: secondaryParts.joined(separator: " · "),
                attributes: [
                    .font: captionFont,
                    .foregroundColor: secondaryInk,
                ]
            )
        }

        configureQuote(payload: payload)

        timestampNode.attributedText = NSAttributedString(
            string: FireTopicPresentation.compactTimestamp(payload.post.createdAt) ?? "",
            attributes: [.font: captionFont, .foregroundColor: tertiaryInk]
        )

        if payload.post.acceptedAnswer {
            acceptedAnswerNode.isHidden = false
            acceptedAnswerNode.attributedText = acceptedAnswerAttributedText()
        } else {
            acceptedAnswerNode.isHidden = true
        }

        postNumberNode.attributedText = NSAttributedString(
            string: "#\(payload.post.postNumber)楼",
            attributes: [.font: monoCaptionFont, .foregroundColor: tertiaryInk]
        )

        // Header `...` is retired — overflow lives in the bottom action strip.
        menuNode.isHidden = true
        menuNode.isEnabled = false
    }

    func acceptedAnswerAttributedText() -> NSAttributedString {
        let font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                weight: .medium
            )
        )
        let result = NSMutableAttributedString()
        if let image = UIImage(
            systemName: "checkmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(font: font)
        )?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal) {
            result.append(NSAttributedString(attachment: NSTextAttachment(image: image)))
            result.append(NSAttributedString(string: " "))
        }
        result.append(NSAttributedString(
            string: "已采纳",
            attributes: [.font: font, .foregroundColor: UIColor.systemGreen]
        ))
        return result
    }

    static func badgeAttributedText(parts: [String]) -> NSAttributedString {
        let captionFont = UIFont.preferredFont(forTextStyle: .caption2)
        let result = NSMutableAttributedString()
        let colors: [UIColor] = [
            UIColor.systemOrange,
            UIColor.systemTeal,
            UIColor.systemIndigo,
            UIColor.systemPink,
        ]
        for (index, part) in parts.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: " "))
            }
            let color = colors[index % colors.count]
            result.append(NSAttributedString(
                string: part,
                attributes: [
                    .font: UIFontMetrics(forTextStyle: .caption2).scaledFont(
                        for: UIFont.systemFont(ofSize: captionFont.pointSize, weight: .semibold)
                    ),
                    .foregroundColor: color,
                    .backgroundColor: color.withAlphaComponent(0.13),
                ]
            ))
        }
        return result
    }

    func showLoadedAvatar() {
        avatarNode.alpha = 1
    }

    func showAvatarFallback() {
        avatarNode.alpha = 0
    }

    func cancelAvatarLoad() {
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        avatarLoadGeneration &+= 1
        avatarNode.image = nil
        showAvatarFallback()
    }

    func loadAvatar(url: URL) {
        avatarLoadTask?.cancel()
        avatarLoadGeneration &+= 1
        let generation = avatarLoadGeneration
        let request = FireRemoteImageRequest(url: url)

        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            avatarNode.image = cachedImage
            showLoadedAvatar()
            return
        }

        avatarNode.image = nil
        showAvatarFallback()
        avatarLoadTask = Task { [weak self] in
            do {
                let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyLoadedAvatar(image, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyFailedAvatarLoad(generation: generation)
                }
            }
        }
    }

    func applyLoadedAvatar(_ image: UIImage, generation: UInt64) {
        guard generation == avatarLoadGeneration else { return }
        avatarNode.image = image
        showLoadedAvatar()
    }

    func applyFailedAvatarLoad(generation: UInt64) {
        guard generation == avatarLoadGeneration else { return }
        avatarNode.image = nil
        showAvatarFallback()
    }
}
