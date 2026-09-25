import UIKit

extension FireRichTextAttributedStringBuilder {
    static let replyQuotePreviewLineLimit = 4
    static let replyQuotePreviewCharacterLimit = 220

    static func quoteBlockAttributedString(
        author: String?,
        postNumber: UInt32?,
        topicId: UInt64?,
        children: [FireRichTextNode],
        context: RenderContext
    ) -> NSAttributedString {
        let content = NSMutableAttributedString()
        let isReplyQuote = !(author?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || postNumber != nil

        if let header = quoteHeaderAttributedString(
            author: author,
            postNumber: postNumber,
            topicId: topicId,
            context: context
        ) {
            content.append(header)
            if !children.isEmpty {
                content.append(NSAttributedString(string: "\n"))
            }
        }

        let body = NSMutableAttributedString()
        // Body blockquotes should read like surrounding post text (web Discourse),
        // while reply-quotes stay slightly de-emphasized.
        let bodyContext = isReplyQuote
            ? context.indented().withTextColor(FireTheme.uiSubtleInk)
            : context.withTextColor(context.textColor)
        appendNodes(children, to: body, context: bodyContext)
        if isReplyQuote {
            content.append(compactReplyQuoteBody(body))
        } else {
            content.append(fullBlockquoteBody(body))
        }

        guard content.length > 0 else {
            return content
        }

        // Discourse-like filled panel — stronger than canvas so the block reads clearly.
        let fill = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1)
            }
            return UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1) // #E6E8ED
        }
        let stripe = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(white: 0.42, alpha: 1)
            }
            return UIColor(red: 0.68, green: 0.71, blue: 0.76, alpha: 1)
        }

        // Include vertical padding in layout height (CALayer pad alone gets clipped).
        let padded = NSMutableAttributedString()
        padded.append(quotePaddingLine())
        padded.append(content)
        padded.append(quotePaddingLine())

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        paragraph.lineSpacing = 3
        paragraph.headIndent = 16
        paragraph.firstLineHeadIndent = 16
        paragraph.tailIndent = -12
        paragraph.lineBreakMode = .byWordWrapping

        padded.addAttributes(
            [
                .paragraphStyle: paragraph,
                .fireQuotePreviewBlock: true,
                .fireQuotePreviewBackgroundColor: fill,
                .fireQuotePreviewStripeColor: stripe,
            ],
            range: NSRange(location: 0, length: padded.length)
        )
        return padded
    }

    static func quotePaddingLine() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 10
        style.maximumLineHeight = 10
        return NSAttributedString(
            string: "\u{200B}\n",
            attributes: [
                .font: UIFont.systemFont(ofSize: 1),
                .foregroundColor: UIColor.clear,
                .paragraphStyle: style,
            ]
        )
    }

    static func fullBlockquoteBody(_ body: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: body)
        // Collapse excessive blank lines inside the quote without truncating content.
        collapseExcessiveBlankLines(in: result)
        if result.length > 0 {
            let font = UIFont.preferredFont(forTextStyle: .body)
            result.addAttributes(
                [
                    .font: font,
                    .foregroundColor: FireTheme.uiInk.withAlphaComponent(0.88),
                ],
                range: NSRange(location: 0, length: result.length)
            )
        }
        return result
    }

    static func compactReplyQuoteBody(_ body: NSAttributedString) -> NSAttributedString {
        let compact = NSMutableAttributedString()
        let source = body.string as NSString
        let ranges = nonBlankLineRanges(in: source)
        let selectedRanges = ranges.isEmpty
            ? trimmedRange(in: source, range: NSRange(location: 0, length: source.length)).map { [$0] } ?? []
            : Array(ranges.prefix(replyQuotePreviewLineLimit))

        for (index, range) in selectedRanges.enumerated() {
            if index > 0 {
                compact.append(NSAttributedString(string: "\n"))
            }
            compact.append(body.attributedSubstring(from: range))
        }

        truncateQuoteBody(compact)
        if compact.length > 0 {
            compact.addAttributes(
                [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: FireTheme.uiSubtleInk,
                ],
                range: NSRange(location: 0, length: compact.length)
            )
        }
        return compact
    }

    static func collapseExcessiveBlankLines(in body: NSMutableAttributedString) {
        var text = body.string as NSString
        while text.contains("\n\n\n") {
            let range = text.range(of: "\n\n\n")
            guard range.location != NSNotFound else { break }
            body.replaceCharacters(in: range, with: "\n\n")
            text = body.string as NSString
        }
    }

    static func nonBlankLineRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var lineStart = 0
        while lineStart <= source.length {
            let searchRange = NSRange(location: lineStart, length: source.length - lineStart)
            let newlineRange = source.range(of: "\n", options: [], range: searchRange)
            let lineEnd = newlineRange.location == NSNotFound ? source.length : newlineRange.location
            if let range = trimmedRange(
                in: source,
                range: NSRange(location: lineStart, length: lineEnd - lineStart)
            ) {
                ranges.append(range)
            }
            if lineEnd >= source.length {
                break
            }
            lineStart = lineEnd + 1
        }
        return ranges
    }

    static func trimmedRange(in source: NSString, range: NSRange) -> NSRange? {
        var location = range.location
        var end = range.location + range.length
        let whitespace = CharacterSet.whitespacesAndNewlines
        while location < end,
              let scalar = UnicodeScalar(source.character(at: location)),
              whitespace.contains(scalar) {
            location += 1
        }
        while end > location,
              let scalar = UnicodeScalar(source.character(at: end - 1)),
              whitespace.contains(scalar) {
            end -= 1
        }
        return location < end
            ? NSRange(location: location, length: end - location)
            : nil
    }

    static func truncateQuoteBody(_ body: NSMutableAttributedString) {
        let maxLength = replyQuotePreviewCharacterLimit
        let ellipsis = "…"
        guard body.length > maxLength else {
            return
        }
        body.deleteCharacters(in: NSRange(location: maxLength - ellipsis.count, length: body.length - (maxLength - ellipsis.count)))
        while body.length > 0,
              let scalar = UnicodeScalar((body.string as NSString).character(at: body.length - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            body.deleteCharacters(in: NSRange(location: body.length - 1, length: 1))
        }
        body.append(NSAttributedString(string: ellipsis))
    }

    static func quoteHeaderAttributedString(
        author: String?,
        postNumber: UInt32?,
        topicId: UInt64?,
        context: RenderContext
    ) -> NSAttributedString? {
        let trimmedAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmedAuthor?.isEmpty == false) || postNumber != nil else {
            return nil
        }

        let font = UIFont.preferredFont(forTextStyle: .caption1)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: FireTheme.uiSubtleInk,
        ]
        let result = NSMutableAttributedString(string: "引用", attributes: baseAttributes)

        if let trimmedAuthor, !trimmedAuthor.isEmpty {
            result.append(NSAttributedString(string: " ", attributes: baseAttributes))
            let profileLink: Any = URL(string: profileURLString(for: trimmedAuthor)) ?? profileURLString(for: trimmedAuthor)
            result.append(NSAttributedString(string: "@\(trimmedAuthor)", attributes: [
                .font: font,
                .foregroundColor: context.accentColor,
                .link: profileLink,
            ]))
        }

        if let postNumber {
            result.append(NSAttributedString(string: " · ", attributes: baseAttributes))
            var postAttributes = baseAttributes
            postAttributes[.foregroundColor] = context.accentColor
            if let topicId {
                postAttributes[.link] = URL(string: topicURLString(topicId: topicId, postNumber: postNumber))
                    ?? topicURLString(topicId: topicId, postNumber: postNumber)
            }
            result.append(NSAttributedString(string: "#\(postNumber)", attributes: postAttributes))
        }

        return result
    }

    static func prefixedLines(
        in attributedString: NSAttributedString,
        prefix: NSAttributedString
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let fullString = attributedString.string as NSString

        guard fullString.length > 0 else {
            return result
        }

        var location = 0
        while location < fullString.length {
            let lineRange = fullString.lineRange(for: NSRange(location: location, length: 0))
            result.append(prefix)
            result.append(attributedString.attributedSubstring(from: lineRange))
            location = NSMaxRange(lineRange)
        }

        return result
    }
}
