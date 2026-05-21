import SwiftUI
import UIKit

// MARK: - Rich Text Data Model

/// Represents a parsed node from Discourse's `cooked` HTML.
/// Designed to be lightweight and Sendable for off-main-thread parsing.
enum FireRichTextNode: Sendable, Equatable {
    case text(String)
    case bold([FireRichTextNode])
    case italic([FireRichTextNode])
    case strikethrough([FireRichTextNode])
    case code(String)
    case codeBlock(language: String?, code: String)
    case link(url: String, children: [FireRichTextNode])
    case mention(username: String)
    case emoji(url: String, fallbackText: String, onlyEmoji: Bool)
    case heading(level: Int, children: [FireRichTextNode])
    case blockquote([FireRichTextNode])
    case quote(author: String?, postNumber: UInt32?, topicId: UInt64?, children: [FireRichTextNode])
    case listItem([FireRichTextNode])
    case lineBreak
    case paragraph([FireRichTextNode])
    case image(src: String, alt: String?, width: CGFloat?, height: CGFloat?)
}

/// Parsed rich text content for a single post.
struct FireRichTextContent: Sendable {
    let nodes: [FireRichTextNode]
    let imageAttachments: [FireCookedImage]
}

// MARK: - HTML → Rich Text Parser

enum FireRichTextParser {
    /// Parse Discourse `cooked` HTML into structured rich text nodes.
    /// This is a lightweight regex/scanner-based parser optimized for the common
    /// HTML patterns emitted by Discourse (not a full HTML parser).
    static func parse(html: String, baseURLString: String) -> FireRichTextContent {
        guard !html.isEmpty else {
            return FireRichTextContent(nodes: [], imageAttachments: [])
        }

        let images = FireTopicPresentation.imageAttachments(from: html, baseURLString: baseURLString)
        let nodes = parseNodes(from: html, baseURLString: baseURLString)
        return FireRichTextContent(nodes: nodes, imageAttachments: images)
    }

    private static func parseNodes(from html: String, baseURLString: String) -> [FireRichTextNode] {
        var result: [FireRichTextNode] = []
        let scanner = Scanner(string: html)
        scanner.charactersToBeSkipped = nil

        while !scanner.isAtEnd {
            if let node = scanTag(scanner: scanner, baseURLString: baseURLString) {
                result.append(node)
            } else if let text = scanner.scanUpToString("<") {
                let decoded = decodeEntities(text)
                if !decoded.isEmpty {
                    result.append(.text(decoded))
                }
            } else if scanner.scanString("<") != nil {
                // Stray '<' — consume as text
                result.append(.text("<"))
            }
        }

        return result
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func scanTag(scanner: Scanner, baseURLString: String) -> FireRichTextNode? {
        let startIndex = scanner.currentIndex
        guard scanner.scanString("<") != nil else { return nil }

        // Closing tags — skip
        if scanner.scanString("/") != nil {
            _ = scanner.scanUpToString(">")
            _ = scanner.scanString(">")
            return nil
        }

        // Tag name
        guard let tagName = scanner.scanCharacters(from: .alphanumerics)?.lowercased() else {
            scanner.currentIndex = startIndex
            return nil
        }

        // Scan attributes
        let attrs = scanAttributes(scanner: scanner)

        // Self-closing or closing >
        _ = scanner.scanString("/")
        guard scanner.scanString(">") != nil else {
            scanner.currentIndex = startIndex
            return nil
        }

        switch tagName {
        case "br":
            return .lineBreak

        case "img":
            let classes = classNames(from: attrs["class"])
            if classes.contains("emoji") {
                let resolvedURL = resolveURL(attrs["src"] ?? "", baseURLString: baseURLString)
                let fallbackText = emojiFallbackText(from: attrs, resolvedURLString: resolvedURL)
                guard !resolvedURL.isEmpty else {
                    return fallbackText.isEmpty ? nil : .text(fallbackText)
                }
                return .emoji(
                    url: resolvedURL,
                    fallbackText: fallbackText,
                    onlyEmoji: classes.contains("only-emoji")
                )
            }
            return nil // Full images rendered separately

        case "p":
            let content = scanInnerContent(scanner: scanner, closingTag: "p", baseURLString: baseURLString)
            return .paragraph(content)

        case "strong", "b":
            let closing = tagName == "strong" ? "strong" : "b"
            let content = scanInnerContent(scanner: scanner, closingTag: closing, baseURLString: baseURLString)
            return .bold(content)

        case "em", "i":
            let closing = tagName == "em" ? "em" : "i"
            let content = scanInnerContent(scanner: scanner, closingTag: closing, baseURLString: baseURLString)
            return .italic(content)

        case "s", "del":
            let closing = tagName
            let content = scanInnerContent(scanner: scanner, closingTag: closing, baseURLString: baseURLString)
            return .strikethrough(content)

        case "code":
            let innerHTML = scanRawInner(scanner: scanner, closingTag: "code")
            return .code(decodeEntities(innerHTML))

        case "pre":
            // Code block: <pre><code class="lang-xxx">...</code></pre>
            let innerHTML = scanRawInner(scanner: scanner, closingTag: "pre")
            let (language, code) = extractCodeBlockContent(from: innerHTML)
            return .codeBlock(language: language, code: code)

        case "a":
            let href = attrs["href"] ?? ""
            let classes = classNames(from: attrs["class"])
            if classes.contains("mention") {
                let content = scanInnerContent(scanner: scanner, closingTag: "a", baseURLString: baseURLString)
                let username = extractTextContent(from: content, includingEmojiFallback: false)
                    .trimmingCharacters(in: .whitespaces)
                let cleanUsername = username.hasPrefix("@") ? String(username.dropFirst()) : username
                return .mention(username: cleanUsername)
            }
            let content = scanInnerContent(scanner: scanner, closingTag: "a", baseURLString: baseURLString)
            let resolvedURL = resolveURL(href, baseURLString: baseURLString)
            if shouldSuppressLinkForInlineImage(
                urlString: resolvedURL,
                classNames: classes,
                children: content
            ) {
                return nil
            }
            return .link(url: resolvedURL, children: content)

        case "blockquote":
            let content = scanInnerContent(scanner: scanner, closingTag: "blockquote", baseURLString: baseURLString)
            return .blockquote(content)

        case "aside":
            let content = scanInnerContent(scanner: scanner, closingTag: "aside", baseURLString: baseURLString)
            let classes = classNames(from: attrs["class"])
            if classes.contains("quote") {
                return .quote(
                    author: normalizedText(attrs["data-username"]),
                    postNumber: attrs["data-post"].flatMap(UInt32.init),
                    topicId: attrs["data-topic"].flatMap(UInt64.init),
                    children: normalizeQuotedChildren(content)
                )
            }
            return .paragraph(content)

        case "li":
            let content = scanInnerContent(scanner: scanner, closingTag: "li", baseURLString: baseURLString)
            return .listItem(content)

        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tagName.last!))!
            let content = scanInnerContent(scanner: scanner, closingTag: tagName, baseURLString: baseURLString)
            return .heading(level: level, children: content)

        case "ul", "ol":
            let content = scanInnerContent(scanner: scanner, closingTag: tagName, baseURLString: baseURLString)
            return .paragraph(content)

        case "div", "span", "details", "summary", "section", "header", "nav":
            let content = scanInnerContent(scanner: scanner, closingTag: tagName, baseURLString: baseURLString)
            return .paragraph(content)

        default:
            // Unknown tag — try to consume content inside it
            let content = scanInnerContent(scanner: scanner, closingTag: tagName, baseURLString: baseURLString)
            return content.count == 1 ? content[0] : .paragraph(content)
        }
    }

    private static func scanAttributes(scanner: Scanner) -> [String: String] {
        var attrs: [String: String] = [:]
        let attrNameChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

        while !scanner.isAtEnd {
            _ = scanner.scanCharacters(from: .whitespaces)
            if scanner.string[scanner.currentIndex...].hasPrefix(">")
                || scanner.string[scanner.currentIndex...].hasPrefix("/>") {
                break
            }

            guard let name = scanner.scanCharacters(from: attrNameChars)?.lowercased() else {
                _ = scanner.scanCharacter()
                continue
            }

            _ = scanner.scanCharacters(from: .whitespaces)
            guard scanner.scanString("=") != nil else {
                attrs[name] = ""
                continue
            }
            _ = scanner.scanCharacters(from: .whitespaces)

            let value: String
            if scanner.scanString("\"") != nil {
                value = scanner.scanUpToString("\"") ?? ""
                _ = scanner.scanString("\"")
            } else if scanner.scanString("'") != nil {
                value = scanner.scanUpToString("'") ?? ""
                _ = scanner.scanString("'")
            } else {
                value = scanner.scanCharacters(from: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ">")).inverted) ?? ""
            }
            attrs[name] = decodeEntities(value)
        }

        return attrs
    }

    private static func scanInnerContent(
        scanner: Scanner,
        closingTag: String,
        baseURLString: String
    ) -> [FireRichTextNode] {
        var nodes: [FireRichTextNode] = []
        let closingPattern = "</\(closingTag)"

        while !scanner.isAtEnd {
            // Check for closing tag
            let remaining = scanner.string[scanner.currentIndex...]
            if remaining.lowercased().hasPrefix(closingPattern.lowercased()) {
                // Consume closing tag
                scanner.currentIndex = scanner.string.index(scanner.currentIndex, offsetBy: closingPattern.count)
                _ = scanner.scanUpToString(">")
                _ = scanner.scanString(">")
                break
            }

            if remaining.hasPrefix("<") {
                if let node = scanTag(scanner: scanner, baseURLString: baseURLString) {
                    nodes.append(node)
                }
            } else {
                let text = scanner.scanUpToString("<") ?? ""
                let decoded = decodeEntities(text)
                if !decoded.isEmpty {
                    nodes.append(.text(decoded))
                }
            }
        }

        return nodes
    }

    private static func scanRawInner(scanner: Scanner, closingTag: String) -> String {
        let closingPattern = "</\(closingTag)"
        var content = ""

        while !scanner.isAtEnd {
            let remaining = scanner.string[scanner.currentIndex...]
            if remaining.lowercased().hasPrefix(closingPattern.lowercased()) {
                scanner.currentIndex = scanner.string.index(scanner.currentIndex, offsetBy: closingPattern.count)
                _ = scanner.scanUpToString(">")
                _ = scanner.scanString(">")
                break
            }
            content.append(scanner.string[scanner.currentIndex])
            scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
        }

        return content
    }

    private static func extractCodeBlockContent(from html: String) -> (language: String?, code: String) {
        // Try to find <code class="lang-xxx"> inner content
        let codePattern = #"<code[^>]*class="[^"]*lang(?:uage)?-([^"\s]+)[^"]*"[^>]*>([\s\S]*?)</code>"#
        if let regex = try? NSRegularExpression(pattern: codePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
            let language = Range(match.range(at: 1), in: html).map { String(html[$0]) }
            let code = Range(match.range(at: 2), in: html).map { String(html[$0]) } ?? ""
            return (language, decodeEntities(stripTags(code)))
        }

        // Fallback: just strip all tags
        let code = stripTags(html)
        return (nil, decodeEntities(code))
    }

    private static func extractTextContent(
        from nodes: [FireRichTextNode],
        includingEmojiFallback: Bool = true
    ) -> String {
        nodes.map { node in
            switch node {
            case .text(let t): return t
            case .bold(let c), .italic(let c), .strikethrough(let c),
                 .paragraph(let c), .heading(_, let c), .blockquote(let c),
                 .quote(_, _, _, let c), .listItem(let c):
                return extractTextContent(from: c, includingEmojiFallback: includingEmojiFallback)
            case .link(_, let c):
                return extractTextContent(from: c, includingEmojiFallback: includingEmojiFallback)
            case .code(let t): return t
            case .codeBlock(_, let t): return t
            case .mention(let u): return "@\(u)"
            case .emoji(_, let fallbackText, _): return includingEmojiFallback ? fallbackText : ""
            case .lineBreak: return "\n"
            case .image: return ""
            }
        }.joined()
    }

    private static func classNames(from rawValue: String?) -> Set<String> {
        Set(
            (rawValue ?? "")
                .split(whereSeparator: { $0.isWhitespace })
                .map { $0.lowercased() }
        )
    }

    private static func normalizeQuotedChildren(_ children: [FireRichTextNode]) -> [FireRichTextNode] {
        let meaningfulChildren = children.filter { child in
            guard case .text(let value) = child else { return true }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard meaningfulChildren.count == 1,
              case .blockquote(let quotedChildren) = meaningfulChildren[0] else {
            return children
        }

        return quotedChildren
    }

    private static func normalizedText(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func shouldSuppressLinkForInlineImage(
        urlString: String,
        classNames: Set<String>,
        children: [FireRichTextNode]
    ) -> Bool {
        let visibleText = extractTextContent(from: children, includingEmojiFallback: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let imageLikeURL = isImageURL(urlString)

        if classNames.contains("lightbox") {
            return true
        }

        if classNames.contains("attachment") && imageLikeURL {
            return visibleText.isEmpty || looksLikeImageFilename(visibleText)
        }

        if children.isEmpty && imageLikeURL {
            return true
        }

        return imageLikeURL && looksLikeImageFilename(visibleText)
    }

    private static func isImageURL(_ urlString: String) -> Bool {
        let normalized = urlString.lowercased()
        return normalized.hasSuffix(".jpg")
            || normalized.hasSuffix(".jpeg")
            || normalized.hasSuffix(".png")
            || normalized.hasSuffix(".gif")
            || normalized.hasSuffix(".webp")
            || normalized.hasSuffix(".avif")
            || normalized.contains("/uploads/")
            || normalized.contains("/original/")
            || normalized.contains("/images/emoji/")
    }

    private static func looksLikeImageFilename(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }
        return isImageURL(value)
    }

    private static func emojiFallbackText(from attrs: [String: String], resolvedURLString: String) -> String {
        if let title = normalizedEmojiFallback(attrs["title"]) {
            return title
        }
        if let alt = normalizedEmojiFallback(attrs["alt"]) {
            return alt
        }
        if let derived = emojiShortcode(from: resolvedURLString) {
            return derived
        }
        return ":emoji:"
    }

    private static func normalizedEmojiFallback(_ rawValue: String?) -> String? {
        guard let rawValue = normalizedText(rawValue) else {
            return nil
        }

        let trimmedColons = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let needsShortcodeWrapping = rawValue.unicodeScalars.contains { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }

        guard needsShortcodeWrapping else {
            return rawValue
        }

        return trimmedColons.isEmpty ? rawValue : ":\(trimmedColons):"
    }

    private static func emojiShortcode(from urlString: String) -> String? {
        guard !urlString.isEmpty else {
            return nil
        }

        let rawPath = URL(string: urlString)?.path ?? urlString
        guard let emojiPathRange = rawPath.range(of: "/images/emoji/") else {
            return nil
        }

        let components = rawPath[emojiPathRange.upperBound...]
            .split(separator: "/")
            .map(String.init)
        guard components.count >= 2 else {
            return nil
        }

        let shortcodeComponents = components.dropFirst().map { component in
            component.replacingOccurrences(of: #"\.[^.]+$"#, with: "", options: .regularExpression)
        }.filter { !$0.isEmpty }

        guard !shortcodeComponents.isEmpty else {
            return nil
        }

        return normalizedEmojiFallback(shortcodeComponents.joined(separator: ":"))
    }

    private static func resolveURL(_ href: String, baseURLString: String) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            return "https:\(trimmed)"
        }
        if trimmed.hasPrefix("/") {
            let base = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "\(base)\(trimmed)"
        }
        return trimmed
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&#160;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""), ("&#34;", "\""),
            ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"),
            ("&lt;", "<"), ("&gt;", ">"),
            ("&#8211;", "–"), ("&#8212;", "—"),
            ("&#8230;", "…"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric entities
        let numericPattern = #"&#(\d+);"#
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result),
                      let codePoint = UInt32(result[codeRange]),
                      let scalar = Unicode.Scalar(codePoint) else { continue }
                result.replaceSubrange(range, with: String(Character(scalar)))
            }
        }
        return result
    }
}

// MARK: - AttributedString Builder

enum FireRichTextAttributedStringBuilder {
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
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                result.append(NSAttributedString(string: code.trimmingCharacters(in: .newlines), attributes: attrs))
                result.append(NSAttributedString(string: "\n"))

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

                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }

                let headingResult = NSMutableAttributedString()
                appendNodes(children, to: headingResult, context: headingContext)
                headingResult.addAttribute(.font, value: headingFont, range: NSRange(location: 0, length: headingResult.length))
                result.append(headingResult)
                result.append(NSAttributedString(string: "\n"))

            case .blockquote(let children):
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }

                let quoteResult = quoteBlockAttributedString(
                    author: nil,
                    postNumber: nil,
                    topicId: nil,
                    children: children,
                    context: context
                )
                result.append(quoteResult)
                if !quoteResult.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }

            case .quote(let author, let postNumber, let topicId, let children):
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }

                let quoteResult = quoteBlockAttributedString(
                    author: author,
                    postNumber: postNumber,
                    topicId: topicId,
                    children: children,
                    context: context
                )
                result.append(quoteResult)
                if !quoteResult.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }

            case .listItem(let children):
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                let bullet = NSAttributedString(string: " • ", attributes: textAttributes(for: context))
                result.append(bullet)
                appendNodes(children, to: result, context: context)

            case .lineBreak:
                result.append(NSAttributedString(string: "\n"))

            case .paragraph(let children):
                if result.length > 0 && !result.string.hasSuffix("\n") && !result.string.hasSuffix("\n\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                appendNodes(children, to: result, context: context)

            case .image:
                break // Handled separately via imageAttachments
            }
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
            baselineOffset: font.descender
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
        content.append(body)

        let prefixed = prefixedLines(
            in: content,
            prefix: NSAttributedString(string: "▍ ", attributes: [
                .font: context.currentFont,
                .foregroundColor: UIColor.separator,
            ])
        )
        guard prefixed.length > 0 else {
            return prefixed
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        paragraph.paragraphSpacingBefore = 4
        paragraph.lineSpacing = 2
        prefixed.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: prefixed.length)
        )
        return prefixed
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
    let attributedString: NSAttributedString
    let onLinkTapped: ((URL) -> Void)?

    init(attributedString: NSAttributedString, onLinkTapped: ((URL) -> Void)? = nil) {
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
        if uiView.attributedText != attributedString {
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

/// Custom UITextView that sizes itself to content.
final class FireRichTextUIView: UITextView {
    private var emojiLoadTasks: [String: Task<Void, Never>] = [:]

    deinit {
        cancelEmojiLoadTasks()
    }

    override var attributedText: NSAttributedString! {
        didSet {
            cancelEmojiLoadTasks()
            loadEmojiAttachmentsIfNeeded()
        }
    }

    override var intrinsicContentSize: CGSize {
        let fixedWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 80
        let size = sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != intrinsicContentSize {
            invalidateIntrinsicContentSize()
        }
    }

    private func cancelEmojiLoadTasks() {
        emojiLoadTasks.values.forEach { $0.cancel() }
        emojiLoadTasks.removeAll()
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
                        self?.emojiLoadTasks.removeValue(forKey: cacheKey)
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
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}
