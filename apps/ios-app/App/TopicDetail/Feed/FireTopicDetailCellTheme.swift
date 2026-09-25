import AsyncDisplayKit
import UIKit

enum FireTopicDetailCellColors {
    static var accent: UIColor { FireTheme.uiAccent }
    static var warning: UIColor { FireTheme.uiWarning }
    static var tagChipBackground: UIColor { FireTheme.uiTagChipBackground }
    static var tagChipForeground: UIColor { FireTheme.uiTagChipForeground }
    static let privateMessageForeground = UIColor.systemIndigo

    static func categoryChipBackground(accent: UIColor) -> UIColor {
        FireTheme.uiCategoryChipBackground(accent: accent)
    }
}


final class FireTopicDetailChipButtonNode: ASButtonNode {
    private let action: (() -> Void)?

    init(action: (() -> Void)?) {
        self.action = action
        super.init()
        addTarget(self, action: #selector(handleTap), forControlEvents: .touchUpInside)
    }

    @objc private func handleTap() {
        action?()
    }
}

enum FireTopicDetailRuntimeTypography {
    static func scaledFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let preferred = UIFont.preferredFont(forTextStyle: textStyle)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: UIFont.systemFont(ofSize: preferred.pointSize, weight: weight)
        )
    }
}
