import UIKit

extension FireRichTextAttributedStringBuilder {
    static func textAttributes(
        for context: RenderContext,
        overrideColor: UIColor? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: context.currentFont,
            .foregroundColor: overrideColor ?? context.textColor,
        ]
        if context.isStrikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    static func headingParagraphStyle(for font: UIFont) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        let lineHeight = ceil(font.lineHeight * 1.12)
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineSpacing = max(2, ceil(font.pointSize * 0.12))
        paragraph.paragraphSpacingBefore = 2
        paragraph.paragraphSpacing = 6
        paragraph.lineBreakMode = .byWordWrapping
        return paragraph
    }

    static func profileURLString(for username: String) -> String {
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return "fire://profile/\(encodedUsername)"
    }

    static func topicURLString(topicId: UInt64, postNumber: UInt32?) -> String {
        if let postNumber {
            return "fire://topic/\(topicId)/\(postNumber)"
        }
        return "fire://topic/\(topicId)"
    }
}
