import UIKit

extension FireRichTextAttributedStringBuilder {
    static func oneboxAttributedString(
        url: String?,
        title: String?,
        description: String?,
        sourceName: String?,
        context: RenderContext
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: FireTheme.uiSubtleInk,
        ]
        let trimmedSource = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = (trimmedSource?.isEmpty == false ? trimmedSource : nil)
            ?? url.flatMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") }
        if let source, !source.isEmpty {
            result.append(NSAttributedString(string: source, attributes: captionAttributes))
        }

        let linkValue: Any?
        if let url {
            linkValue = URL(string: url) ?? url
        } else {
            linkValue = nil
        }
        let titleText = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionText = description?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let titleText, !titleText.isEmpty {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            var attrs = textAttributes(for: context.withBold())
            attrs[.foregroundColor] = context.accentColor
            if let linkValue {
                attrs[.link] = linkValue
            }
            result.append(NSAttributedString(string: titleText, attributes: attrs))
        }

        if let descriptionText, !descriptionText.isEmpty {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(NSAttributedString(
                string: descriptionText,
                attributes: textAttributes(for: context.withTextColor(FireTheme.uiSubtleInk))
            ))
        } else if let url, !url.isEmpty, titleText?.isEmpty != false {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            var attrs = textAttributes(for: context)
            attrs[.foregroundColor] = context.accentColor
            if let linkValue {
                attrs[.link] = linkValue
            }
            result.append(NSAttributedString(string: url, attributes: attrs))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        paragraph.paragraphSpacingBefore = 4
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
}
