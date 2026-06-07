import SwiftUI
import UIKit

extension NSAttributedString.Key {
    static let fireQuotePreviewBlock = NSAttributedString.Key("FireQuotePreviewBlock")
    static let fireQuotePreviewBackgroundColor = NSAttributedString.Key("FireQuotePreviewBackgroundColor")
    static let fireQuotePreviewStripeColor = NSAttributedString.Key("FireQuotePreviewStripeColor")
}

// MARK: - Rich Text Data Model

/// Native display node adapted from the shared Rust RenderDocument.
/// Designed to be lightweight and Sendable for off-main-thread rendering.
enum FireRichTextNode: Sendable, Equatable {
    case text(String)
    case bold([FireRichTextNode])
    case italic([FireRichTextNode])
    case strikethrough([FireRichTextNode])
    case code(String)
    case codeBlock(language: String?, code: String)
    case link(url: String, children: [FireRichTextNode])
    case mention(username: String)
    case mentionGroup(name: String, url: String)
    case hashtag(text: String, url: String, kind: String?)
    case emoji(url: String, fallbackText: String, onlyEmoji: Bool)
    case heading(level: Int, children: [FireRichTextNode])
    case blockquote([FireRichTextNode])
    case quote(author: String?, postNumber: UInt32?, topicId: UInt64?, children: [FireRichTextNode])
    case onebox(url: String?, title: String?, description: String?)
    case list(ordered: Bool, items: [[FireRichTextNode]])
    case listItem([FireRichTextNode])
    case spoiler([FireRichTextNode])
    case details(summary: [FireRichTextNode], children: [FireRichTextNode])
    case table(String)
    case video(url: String, title: String?)
    case divider
    case lineBreak
    case paragraph([FireRichTextNode])
    case image(src: String, alt: String?, width: CGFloat?, height: CGFloat?)
}

/// RenderDocument content adapted for native post display.
struct FireRichTextContent: Sendable {
    let nodes: [FireRichTextNode]
    let plainText: String
    let imageAttachments: [FireCookedImage]
}

// MARK: - AttributedString Builder

enum FireRichTextAttributedStringBuilder {
    private static let quotePreviewLineLimit = 2
    private static let quotePreviewCharacterLimit = 120

    /// Convert parsed nodes into an NSAttributedString suitable for display.
    static func build(
        from nodes: [FireRichTextNode],
        baseFont: UIFont = .preferredFont(forTextStyle: .subheadline),
        textColor: UIColor = .label,
        accentColor: UIColor = .systemBlue,
        codeBackgroundColor: UIColor = .secondarySystemBackground
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        appendNodes(nodes, to: result, context: RenderContext(
            baseFont: baseFont,
            textColor: textColor,
            accentColor: accentColor,
            codeBackgroundColor: codeBackgroundColor,
            isBold: false,
            isItalic: false,
            isStrikethrough: false,
            indentLevel: 0
        ))
        return result
    }

    private struct RenderContext {
        let baseFont: UIFont
        let textColor: UIColor
        let accentColor: UIColor
        let codeBackgroundColor: UIColor
        var isBold: Bool
        var isItalic: Bool
        var isStrikethrough: Bool
        var indentLevel: Int

        var currentFont: UIFont {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if isBold { traits.insert(.traitBold) }
            if isItalic { traits.insert(.traitItalic) }
            if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                return UIFont(descriptor: descriptor, size: baseFont.pointSize)
            }
            return baseFont
        }

        func withBold() -> RenderContext {
            var ctx = self; ctx.isBold = true; return ctx
        }
        func withItalic() -> RenderContext {
            var ctx = self; ctx.isItalic = true; return ctx
        }
        func withStrikethrough() -> RenderContext {
            var ctx = self; ctx.isStrikethrough = true; return ctx
        }
        func indented() -> RenderContext {
            var ctx = self; ctx.indentLevel += 1; return ctx
        }
        func withTextColor(_ color: UIColor) -> RenderContext {
            RenderContext(
                baseFont: baseFont,
                textColor: color,
                accentColor: accentColor,
                codeBackgroundColor: codeBackgroundColor,
                isBold: isBold,
                isItalic: isItalic,
                isStrikethrough: isStrikethrough,
                indentLevel: indentLevel
            )
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func appendNodes(
        _ nodes: [FireRichTextNode],
        to result: NSMutableAttributedString,
        context: RenderContext
    ) {
        for node in nodes {
            switch node {
            case .text(let text):
                let attrs = textAttributes(for: context)
                result.append(NSAttributedString(string: text, attributes: attrs))

            case .bold(let children):
                appendNodes(children, to: result, context: context.withBold())

            case .italic(let children):
                appendNodes(children, to: result, context: context.withItalic())

            case .strikethrough(let children):
                appendNodes(children, to: result, context: context.withStrikethrough())

            case .code(let text):
                let codeFont = UIFont.monospacedSystemFont(
                    ofSize: context.baseFont.pointSize - 1,
                    weight: .regular
                )
                var attrs = textAttributes(for: context)
                attrs[.font] = codeFont
                attrs[.backgroundColor] = context.codeBackgroundColor
                result.append(NSAttributedString(string: text, attributes: attrs))

            case .codeBlock(_, let code):
                ensureBlockBoundary(result)
                let codeFont = UIFont.monospacedSystemFont(
                    ofSize: context.baseFont.pointSize - 1,
                    weight: .regular
                )
                let paragraph = NSMutableParagraphStyle()
                paragraph.firstLineHeadIndent = 12
                paragraph.headIndent = 12
                paragraph.tailIndent = -12
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: codeFont,
                    .foregroundColor: context.textColor,
                    .backgroundColor: context.codeBackgroundColor,
                    .paragraphStyle: paragraph,
                ]
                result.append(NSAttributedString(string: code.trimmingCharacters(in: .newlines), attributes: attrs))

            case .link(let url, let children):
                let linkText = NSMutableAttributedString()
                appendNodes(children, to: linkText, context: context)
                let linkValue: Any = URL(string: url) ?? url
                // Apply link attribute to entire range
                linkText.addAttributes([
                    .foregroundColor: context.accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: linkValue,
                ], range: NSRange(location: 0, length: linkText.length))
                result.append(linkText)

            case .mention(let username):
                let linkValue: Any = URL(string: profileURLString(for: username)) ?? profileURLString(for: username)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: context.currentFont,
                    .foregroundColor: context.accentColor,
                    .link: linkValue,
                ]
                result.append(NSAttributedString(string: "@\(username)", attributes: attrs))

            case .mentionGroup(let name, let url):
                let linkValue: Any = URL(string: url) ?? url
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: context.currentFont,
                    .foregroundColor: context.accentColor,
                    .link: linkValue,
                ]
                result.append(NSAttributedString(string: "@\(name)", attributes: attrs))

            case .hashtag(let text, let url, _):
                let linkValue: Any = URL(string: url) ?? url
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: context.currentFont,
                    .foregroundColor: context.accentColor,
                    .link: linkValue,
                ]
                result.append(NSAttributedString(string: "#\(text)", attributes: attrs))

            case .emoji(let url, let fallbackText, let onlyEmoji):
                if let attachment = makeEmojiAttachment(
                    urlString: url,
                    fallbackText: fallbackText,
                    font: context.currentFont,
                    onlyEmoji: onlyEmoji
                ) {
                    result.append(NSAttributedString(attachment: attachment))
                } else {
                    result.append(NSAttributedString(string: fallbackText, attributes: textAttributes(for: context)))
                }

            case .heading(let level, let children):
                ensureBlockBoundary(result)
                let headingSize: CGFloat
                switch level {
                case 1: headingSize = context.baseFont.pointSize + 6
                case 2: headingSize = context.baseFont.pointSize + 4
                case 3: headingSize = context.baseFont.pointSize + 2
                default: headingSize = context.baseFont.pointSize + 1
                }
                let headingFont = UIFont.systemFont(ofSize: headingSize, weight: .bold)
                var headingContext = context
                headingContext.isBold = true
                let headingResult = NSMutableAttributedString()
                appendNodes(children, to: headingResult, context: headingContext)
                let headingRange = NSRange(location: 0, length: headingResult.length)
                headingResult.addAttributes([
                    .font: headingFont,
                    .paragraphStyle: headingParagraphStyle(for: headingFont),
                ], range: headingRange)
                result.append(headingResult)

            case .blockquote(let children):
                ensureBlockBoundary(result)
                let quoteResult = quoteBlockAttributedString(
                    author: nil,
                    postNumber: nil,
                    topicId: nil,
                    children: children,
                    context: context
                )
                result.append(quoteResult)

            case .quote(let author, let postNumber, let topicId, let children):
                ensureBlockBoundary(result)
                let quoteResult = quoteBlockAttributedString(
                    author: author,
                    postNumber: postNumber,
                    topicId: topicId,
                    children: children,
                    context: context
                )
                result.append(quoteResult)

            case .onebox(let url, let title, let description):
                ensureBlockBoundary(result)
                result.append(oneboxAttributedString(
                    url: url,
                    title: title,
                    description: description,
                    context: context
                ))

            case .list(let ordered, let items):
                ensureBlockBoundary(result)
                for (index, item) in items.enumerated() {
                    if index > 0 {
                        ensureLineBreak(result)
                    }
                    appendListItem(
                        item,
                        marker: ordered ? "\(index + 1). " : "• ",
                        to: result,
                        context: context
                    )
                }

            case .listItem(let children):
                ensureLineBreak(result)
                appendListItem(
                    children,
                    marker: "• ",
                    to: result,
                    context: context
                )

            case .spoiler(let children):
                let spoiler = NSMutableAttributedString()
                appendNodes(children, to: spoiler, context: context)
                if spoiler.length > 0 {
                    spoiler.addAttributes([
                        .backgroundColor: UIColor.tertiarySystemFill,
                        .foregroundColor: UIColor.secondaryLabel,
                    ], range: NSRange(location: 0, length: spoiler.length))
                    result.append(spoiler)
                }

            case .details(let summary, let children):
                ensureBlockBoundary(result)
                let summaryResult = NSMutableAttributedString(
                    string: "▾ ",
                    attributes: textAttributes(for: context)
                )
                appendNodes(summary, to: summaryResult, context: context.withBold())
                result.append(summaryResult)
                if !children.isEmpty {
                    ensureLineBreak(result)
                    appendNodes(children, to: result, context: context.indented())
                }

            case .table(let text):
                ensureBlockBoundary(result)
                var attrs = textAttributes(for: context)
                attrs[.font] = UIFont.monospacedSystemFont(
                    ofSize: context.baseFont.pointSize - 1,
                    weight: .regular
                )
                attrs[.backgroundColor] = context.codeBackgroundColor
                result.append(NSAttributedString(string: text, attributes: attrs))

            case .video(let url, let title):
                let display = title?.isEmpty == false ? title! : url
                let linkValue: Any = URL(string: url) ?? url
                result.append(NSAttributedString(string: display, attributes: [
                    .font: context.currentFont,
                    .foregroundColor: context.accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: linkValue,
                ]))

            case .divider:
                ensureBlockBoundary(result)
                result.append(NSAttributedString(
                    string: "----------",
                    attributes: textAttributes(for: context.withTextColor(.separator))
                ))

            case .lineBreak:
                result.append(NSAttributedString(string: "\n"))

            case .paragraph(let children):
                ensureBlockBoundary(result)
                appendNodes(children, to: result, context: context)

            case .image:
                break // Handled separately via imageAttachments
            }
        }
    }

    private static func appendListItem(
        _ item: [FireRichTextNode],
        marker: String,
        to result: NSMutableAttributedString,
        context: RenderContext
    ) {
        let start = result.length
        result.append(NSAttributedString(string: marker, attributes: textAttributes(for: context)))
        appendListItemContent(item, to: result, context: context.indented())
        guard result.length > start else {
            return
        }
        result.addAttribute(
            .paragraphStyle,
            value: listParagraphStyle(marker: marker, context: context),
            range: NSRange(location: start, length: result.length - start)
        )
    }

    private static func appendListItemContent(
        _ item: [FireRichTextNode],
        to result: NSMutableAttributedString,
        context: RenderContext
    ) {
        guard let first = item.first else {
            return
        }

        if case .paragraph(let children) = first {
            appendNodes(children, to: result, context: context)
            let remaining = Array(item.dropFirst())
            if !remaining.isEmpty {
                appendNodes(remaining, to: result, context: context)
            }
            return
        }

        appendNodes(item, to: result, context: context)
    }

    private static func listParagraphStyle(marker: String, context: RenderContext) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let baseIndent = CGFloat(context.indentLevel) * 18
        let markerWidth = ceil((marker as NSString).size(withAttributes: [
            .font: context.currentFont,
        ]).width)
        style.firstLineHeadIndent = baseIndent
        style.headIndent = baseIndent + markerWidth
        style.paragraphSpacing = 2
        style.lineBreakMode = .byWordWrapping
        return style
    }

    /// Ensures the next block starts after a single blank-line boundary.
    private static func ensureBlockBoundary(_ result: NSMutableAttributedString) {
        trimTrailingSpaces(result)
        guard result.length > 0 else { return }
        let text = result.string as NSString
        let newlineChar: unichar = 10
        var trailingNewlines = 0
        var idx = text.length - 1
        while idx >= 0 && text.character(at: idx) == newlineChar {
            trailingNewlines += 1
            idx -= 1
        }
        if trailingNewlines > 2 {
            let deleteStart = idx + 3
            result.deleteCharacters(in: NSRange(location: deleteStart, length: trailingNewlines - 2))
        }
        if trailingNewlines == 0 {
            result.append(NSAttributedString(string: "\n\n"))
        } else if trailingNewlines == 1 {
            result.append(NSAttributedString(string: "\n"))
        }
    }

    /// Ensures exactly one trailing newline (for line breaks within blocks).
    private static func ensureLineBreak(_ result: NSMutableAttributedString) {
        trimTrailingSpaces(result)
        guard result.length > 0 else { return }
        let text = result.string as NSString
        let newlineChar: unichar = 10
        if text.length > 0 && text.character(at: text.length - 1) != newlineChar {
            result.append(NSAttributedString(string: "\n"))
        }
    }

    /// Removes trailing space and tab characters from the attributed string.
    private static func trimTrailingSpaces(_ result: NSMutableAttributedString) {
        let text = result.string as NSString
        let spaceChar: unichar = 32
        let tabChar: unichar = 9
        var end = text.length
        while end > 0 {
            let char = text.character(at: end - 1)
            if char != spaceChar && char != tabChar { break }
            end -= 1
        }
        if end < text.length {
            result.deleteCharacters(in: NSRange(location: end, length: text.length - end))
        }
    }

    private static func textAttributes(
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

    private static func oneboxAttributedString(
        url: String?,
        title: String?,
        description: String?,
        context: RenderContext
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        result.append(NSAttributedString(string: "链接预览", attributes: captionAttributes))

        let linkValue: Any?
        if let url {
            linkValue = URL(string: url) ?? url
        } else {
            linkValue = nil
        }
        let titleText = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionText = description?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let titleText, !titleText.isEmpty {
            result.append(NSAttributedString(string: "\n"))
            var attrs = textAttributes(for: context.withBold())
            attrs[.foregroundColor] = context.accentColor
            if let linkValue {
                attrs[.link] = linkValue
            }
            result.append(NSAttributedString(string: titleText, attributes: attrs))
        }

        if let descriptionText, !descriptionText.isEmpty {
            result.append(NSAttributedString(string: "\n"))
            result.append(NSAttributedString(
                string: descriptionText,
                attributes: textAttributes(for: context.withTextColor(.secondaryLabel))
            ))
        } else if let url, !url.isEmpty, titleText?.isEmpty != false {
            result.append(NSAttributedString(string: "\n"))
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

    private static func headingParagraphStyle(for font: UIFont) -> NSParagraphStyle {
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

    private static func makeEmojiAttachment(
        urlString: String,
        fallbackText: String,
        font: UIFont,
        onlyEmoji: Bool
    ) -> FireRichTextEmojiAttachment? {
        guard let url = URL(string: urlString) else {
            return nil
        }

        let displaySize = onlyEmoji
            ? max(font.pointSize * 1.9, font.pointSize + 10)
            : max(font.pointSize * 1.15, font.pointSize + 1)

        return FireRichTextEmojiAttachment(
            remoteURL: url,
            fallbackText: fallbackText,
            displaySize: displaySize,
            baselineOffset: font.descender - max(displaySize - font.lineHeight, 0) / 2
        )
    }

    private static func quoteBlockAttributedString(
        author: String?,
        postNumber: UInt32?,
        topicId: UInt64?,
        children: [FireRichTextNode],
        context: RenderContext
    ) -> NSAttributedString {
        let content = NSMutableAttributedString()

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
        appendNodes(
            children,
            to: body,
            context: context.indented().withTextColor(.secondaryLabel)
        )
        content.append(compactQuoteBody(body))

        guard content.length > 0 else {
            return content
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 8
        paragraph.paragraphSpacingBefore = 4
        paragraph.lineSpacing = 1.5
        paragraph.headIndent = 10
        paragraph.firstLineHeadIndent = 10
        paragraph.tailIndent = -10
        content.addAttributes(
            [
                .paragraphStyle: paragraph,
                .backgroundColor: UIColor.secondarySystemBackground,
                .fireQuotePreviewBlock: true,
                .fireQuotePreviewBackgroundColor: UIColor.secondarySystemBackground,
                .fireQuotePreviewStripeColor: UIColor.tertiaryLabel,
            ],
            range: NSRange(location: 0, length: content.length)
        )
        return content
    }

    private static func compactQuoteBody(_ body: NSAttributedString) -> NSAttributedString {
        let compact = NSMutableAttributedString()
        let source = body.string as NSString
        let ranges = nonBlankLineRanges(in: source)
        let selectedRanges = ranges.isEmpty
            ? trimmedRange(in: source, range: NSRange(location: 0, length: source.length)).map { [$0] } ?? []
            : Array(ranges.prefix(quotePreviewLineLimit))

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
                    .font: UIFont.preferredFont(forTextStyle: .footnote),
                    .foregroundColor: UIColor.secondaryLabel,
                ],
                range: NSRange(location: 0, length: compact.length)
            )
        }
        return compact
    }

    private static func nonBlankLineRanges(in source: NSString) -> [NSRange] {
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

    private static func trimmedRange(in source: NSString, range: NSRange) -> NSRange? {
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

    private static func truncateQuoteBody(_ body: NSMutableAttributedString) {
        let maxLength = quotePreviewCharacterLimit
        let ellipsis = "..."
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

    private static func quoteHeaderAttributedString(
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
            .foregroundColor: UIColor.secondaryLabel,
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

    private static func prefixedLines(
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

    private static func profileURLString(for username: String) -> String {
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return "fire://profile/\(encodedUsername)"
    }

    private static func topicURLString(topicId: UInt64, postNumber: UInt32?) -> String {
        if let postNumber {
            return "fire://topic/\(topicId)/\(postNumber)"
        }
        return "fire://topic/\(topicId)"
    }
}

final class FireRichTextEmojiAttachment: NSTextAttachment {
    let remoteURL: URL
    let fallbackText: String
    let cacheKey: String
    let request: FireRemoteImageRequest

    init(
        remoteURL: URL,
        fallbackText: String,
        displaySize: CGFloat,
        baselineOffset: CGFloat
    ) {
        self.remoteURL = remoteURL
        self.fallbackText = fallbackText
        self.cacheKey = remoteURL.absoluteString
        self.request = FireRemoteImageRequest(url: remoteURL)
        super.init(data: nil, ofType: nil)
        bounds = CGRect(x: 0, y: baselineOffset, width: displaySize, height: displaySize)
        image = Self.placeholderImage(size: displaySize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyLoadedImage(_ loadedImage: UIImage) {
        image = loadedImage.preparingForDisplay() ?? loadedImage
    }

    private static func placeholderImage(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: max(size, 1), height: max(size, 1)))
        return renderer.image { _ in }
    }
}

// MARK: - SwiftUI Integration

/// A UIViewRepresentable that displays rich attributed text with interactive links.
struct FireRichTextView: UIViewRepresentable {
    let contentID: String
    let attributedString: NSAttributedString
    let onLinkTapped: ((URL) -> Void)?

    init(
        contentID: String,
        attributedString: NSAttributedString,
        onLinkTapped: ((URL) -> Void)? = nil
    ) {
        self.contentID = contentID
        self.attributedString = attributedString
        self.onLinkTapped = onLinkTapped
    }

    func makeUIView(context: Context) -> FireRichTextUIView {
        let view = FireRichTextUIView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.backgroundColor = .clear
        view.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: FireRichTextUIView, context: Context) {
        if uiView.renderedContentID != contentID {
            uiView.renderedContentID = contentID
            uiView.attributedText = attributedString
            uiView.invalidateIntrinsicContentSize()
        }
        context.coordinator.onLinkTapped = onLinkTapped
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTapped: onLinkTapped)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var onLinkTapped: ((URL) -> Void)?

        init(onLinkTapped: ((URL) -> Void)?) {
            self.onLinkTapped = onLinkTapped
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            onLinkTapped?(URL)
            return false
        }
    }
}

class FireRichTextTextView: UITextView {
    private var quotePreviewLayers: [CALayer] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        updateQuotePreviewLayers()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateQuotePreviewLayers()
    }

    func refreshQuotePreviewLayers() {
        updateQuotePreviewLayers()
    }

    private func updateQuotePreviewLayers() {
        quotePreviewLayers.forEach { $0.removeFromSuperlayer() }
        quotePreviewLayers.removeAll()

        guard let attributedText,
              attributedText.length > 0,
              bounds.width > 1 else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttribute(.fireQuotePreviewBlock, in: fullRange) { [weak self] value, range, _ in
            guard let self, value != nil else {
                return
            }
            self.addQuotePreviewLayer(for: range, attributedText: attributedText)
        }
    }

    private func addQuotePreviewLayer(for characterRange: NSRange, attributedText: NSAttributedString) {
        guard characterRange.length > 0 else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else {
            return
        }

        var unionRect = CGRect.null
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            guard NSIntersectionRange(glyphRange, lineGlyphRange).length > 0 else {
                return
            }
            let lineRect = CGRect(
                x: self.textContainerInset.left,
                y: self.textContainerInset.top + usedRect.minY - self.contentOffset.y,
                width: max(self.bounds.width - self.textContainerInset.left - self.textContainerInset.right, 1),
                height: usedRect.height
            )
            unionRect = unionRect.isNull ? lineRect : unionRect.union(lineRect)
        }

        guard !unionRect.isNull else {
            return
        }

        let backgroundColor = attributedText.attribute(
            .fireQuotePreviewBackgroundColor,
            at: characterRange.location,
            effectiveRange: nil
        ) as? UIColor ?? .secondarySystemBackground
        let stripeColor = attributedText.attribute(
            .fireQuotePreviewStripeColor,
            at: characterRange.location,
            effectiveRange: nil
        ) as? UIColor ?? .tertiaryLabel

        let backgroundRect = unionRect
            .insetBy(dx: 0, dy: -6)
            .intersection(bounds.insetBy(dx: 0, dy: -2))
        guard !backgroundRect.isNull else {
            return
        }

        let backgroundLayer = CAShapeLayer()
        backgroundLayer.fillColor = backgroundColor.resolvedColor(with: traitCollection).cgColor
        backgroundLayer.path = UIBezierPath(
            roundedRect: backgroundRect,
            cornerRadius: 8
        ).cgPath
        layer.insertSublayer(backgroundLayer, at: 0)
        quotePreviewLayers.append(backgroundLayer)

        let stripeRect = CGRect(
            x: backgroundRect.minX + 8,
            y: backgroundRect.minY + 8,
            width: 3,
            height: max(backgroundRect.height - 16, 1)
        )
        let stripeLayer = CAShapeLayer()
        stripeLayer.fillColor = stripeColor.resolvedColor(with: traitCollection).cgColor
        stripeLayer.path = UIBezierPath(
            roundedRect: stripeRect,
            cornerRadius: 1.5
        ).cgPath
        layer.insertSublayer(stripeLayer, above: backgroundLayer)
        quotePreviewLayers.append(stripeLayer)
    }
}

/// Custom UITextView that sizes itself to content.
final class FireRichTextUIView: FireRichTextTextView {
    private static let intrinsicHeightCache = NSCache<NSString, NSNumber>()

    var renderedContentID: String?
    private var emojiLoadTasks: [String: Task<Void, Never>] = [:]
    private var measuredWidth: CGFloat = 0
    private var cachedIntrinsicHeight: CGFloat?

    deinit {
        cancelEmojiLoadTasks()
    }

    override var attributedText: NSAttributedString! {
        didSet {
            resetIntrinsicMeasurement()
            cancelEmojiLoadTasks()
            loadEmojiAttachmentsIfNeeded()
            refreshQuotePreviewLayers()
        }
    }

    override var intrinsicContentSize: CGSize {
        let width = resolvedMeasurementWidth()
        if let cachedIntrinsicHeight, abs(width - measuredWidth) < 0.5 {
            return CGSize(width: UIView.noIntrinsicMetric, height: cachedIntrinsicHeight)
        }

        if let renderedContentID,
           let cachedHeight = Self.intrinsicHeightCache.object(
               forKey: intrinsicHeightCacheKey(contentID: renderedContentID, width: width)
           ) {
            measuredWidth = width
            cachedIntrinsicHeight = CGFloat(truncating: cachedHeight)
            return CGSize(width: UIView.noIntrinsicMetric, height: CGFloat(truncating: cachedHeight))
        }

        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let resolvedHeight = ceil(size.height)
        measuredWidth = width
        cachedIntrinsicHeight = resolvedHeight
        if let renderedContentID {
            Self.intrinsicHeightCache.setObject(
                NSNumber(value: resolvedHeight),
                forKey: intrinsicHeightCacheKey(contentID: renderedContentID, width: width)
            )
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: resolvedHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = resolvedMeasurementWidth()
        if abs(width - measuredWidth) >= 0.5 {
            cachedIntrinsicHeight = nil
            invalidateIntrinsicContentSize()
        }
    }

    private func resolvedMeasurementWidth() -> CGFloat {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 80
        return max(width, 1)
    }

    private func cancelEmojiLoadTasks() {
        emojiLoadTasks.values.forEach { $0.cancel() }
        emojiLoadTasks.removeAll()
    }

    private func resetIntrinsicMeasurement() {
        measuredWidth = 0
        cachedIntrinsicHeight = nil
    }

    private func intrinsicHeightCacheKey(contentID: String, width: CGFloat) -> NSString {
        let scaledWidth = Int((width * UIScreen.main.scale).rounded())
        return "\(contentID)|w:\(scaledWidth)" as NSString
    }

    private func loadEmojiAttachmentsIfNeeded() {
        guard attributedText.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttribute(.attachment, in: fullRange) { [weak self] value, _, _ in
            guard let self,
                  let attachment = value as? FireRichTextEmojiAttachment else {
                return
            }

            let cacheKey = attachment.cacheKey
            guard emojiLoadTasks[cacheKey] == nil else {
                return
            }

            if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: attachment.request) {
                applyEmojiImage(cachedImage, for: cacheKey)
                return
            }

            emojiLoadTasks[cacheKey] = Task { [weak self] in
                do {
                    let image = try await FireRemoteImagePipeline.shared.loadImage(for: attachment.request)
                    guard !Task.isCancelled else {
                        return
                    }
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        self.applyEmojiImage(image, for: cacheKey)
                        self.emojiLoadTasks.removeValue(forKey: cacheKey)
                    }
                } catch {
                    await MainActor.run {
                        _ = self?.emojiLoadTasks.removeValue(forKey: cacheKey)
                    }
                }
            }
        }
    }

    private func applyEmojiImage(_ image: UIImage, for cacheKey: String) {
        guard textStorage.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        var changedRange = NSRange(location: NSNotFound, length: 0)
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? FireRichTextEmojiAttachment,
                  attachment.cacheKey == cacheKey else {
                return
            }
            attachment.applyLoadedImage(image)
            textStorage.addAttribute(.attachment, value: attachment, range: range)
            changedRange = changedRange.location == NSNotFound
                ? range
                : NSUnionRange(changedRange, range)
        }
        textStorage.endEditing()

        guard changedRange.location != NSNotFound else {
            return
        }

        layoutManager.invalidateDisplay(forCharacterRange: changedRange)
        setNeedsLayout()
    }
}
