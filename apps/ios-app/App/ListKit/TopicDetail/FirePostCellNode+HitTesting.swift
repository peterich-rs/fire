import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    @objc func handleImageTap(_ sender: FirePostImageNode) {
        currentCallbacks?.onOpenImage(sender.image)
    }

    @objc func handleProfileTapGesture(_ gesture: UITapGestureRecognizer) {
        _ = handleProfileTap(at: gesture.location(in: view))
    }

    @discardableResult
    func handleProfileTap(at point: CGPoint) -> Bool {
        guard profileHitRects().contains(where: { $0.contains(point) }) else {
            return false
        }
        guard let username = currentPayload?.post.username.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty else {
            return false
        }
        FireMotionHaptics.selection()
        currentCallbacks?.onOpenProfile(username)
        return true
    }

    func profileHitRects() -> [CGRect] {
        var rects: [CGRect] = []
        if isNodeLoaded {
            let avatar = avatarContainerNode.view.convert(avatarContainerNode.view.bounds, to: view)
            if !avatar.isNull, avatar.width > 1, avatar.height > 1 {
                rects.append(avatar.insetBy(dx: -8, dy: -8))
            }
            if !usernameNode.isHidden {
                let name = usernameNode.view.convert(usernameNode.view.bounds, to: view)
                if !name.isNull, name.width > 1, name.height > 1 {
                    rects.append(name.insetBy(dx: -4, dy: -6))
                }
            }
        }
        if let layout = currentResolvedLayout {
            rects.append(layout.avatarFrame.insetBy(dx: -8, dy: -8))
            let meta = layout.metaFrame
            if !meta.isNull, !meta.isEmpty {
                rects.append(
                    CGRect(x: meta.minX, y: meta.minY, width: min(meta.width, 168), height: meta.height)
                        .insetBy(dx: -4, dy: -6)
                )
            }
        }
        if rects.isEmpty {
            let indent = FirePostCellLayoutCalculator.indentWidth(for: currentDepth)
            rects.append(
                CGRect(
                    x: FirePostCellLayoutCalculator.outerHorizontalPadding + indent,
                    y: 0,
                    width: currentAvatarSize,
                    height: currentAvatarSize
                ).insetBy(dx: -8, dy: -8)
            )
        }
        return rects
    }

    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}
