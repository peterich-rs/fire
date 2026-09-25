import UIKit

/// Compatibility alias for existing UIKit list call sites.
/// Prefer `FireTheme.ui*` for new code; this type only forwards to FireTheme.
enum FireTopicListPalette {
    static var accent: UIColor { FireTheme.uiAccent }
    static var subtleInk: UIColor { FireTheme.uiSubtleInk }
    static var tertiaryInk: UIColor { FireTheme.uiTertiaryInk }
    static var tagChipBackground: UIColor { FireTheme.uiTagChipBackground }
    static var tagChipForeground: UIColor { FireTheme.uiTagChipForeground }

    static func categoryChipBackground(accent: UIColor) -> UIColor {
        FireTheme.uiCategoryChipBackground(accent: accent)
    }
}

extension UIFont {
    func withWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

extension UIColor {
    convenience init?(fireHex hex: String?) {
        guard let hex else {
            return nil
        }
        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
