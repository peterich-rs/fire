import AsyncDisplayKit
import UIKit

// MARK: - Link Delegate

final class RichTextNodeLinkDelegate: NSObject, ASTextNodeDelegate {
    private let onLink: (URL) -> Void
    private let onTruncation: () -> Void

    init(onLink: @escaping (URL) -> Void, onTruncation: @escaping () -> Void) {
        self.onLink = onLink
        self.onTruncation = onTruncation
    }

    func textNode(_ textNode: ASTextNode, tappedLinkAttribute attribute: String, value: Any, at point: CGPoint, textRange: NSRange) {
        if let url = value as? URL {
            onLink(url)
        } else if let string = value as? String, let url = URL(string: string) {
            onLink(url)
        }
    }

    func textNodeTappedTruncationToken(_ textNode: ASTextNode) {
        onTruncation()
    }
}
