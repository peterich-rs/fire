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
    case heading(level: Int, children: [FireRichTextNode])
    case blockquote([FireRichTextNode])
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
            // Images are handled via imageAttachments — skip inline emoji
            let classes = attrs["class"] ?? ""
            if classes.contains("emoji") {
                let alt = attrs["alt"] ?? ""
                return alt.isEmpty ? nil : .text(alt)
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
            let classes = attrs["class"] ?? ""
            if classes.contains("mention") {
                let content = scanInnerContent(scanner: scanner, closingTag: "a", baseURLString: baseURLString)
                let username = extractTextContent(from: content).trimmingCharacters(in: .whitespaces)
                let cleanUsername = username.hasPrefix("@") ? String(username.dropFirst()) : username
                return .mention(username: cleanUsername)
            }
            let content = scanInnerContent(scanner: scanner, closingTag: "a", baseURLString: baseURLString)
            let resolvedURL = resolveURL(href, baseURLString: baseURLString)
            return .link(url: resolvedURL, children: content)

        case "blockquote":
            let content = scanInnerContent(scanner: scanner, closingTag: "blockquote", baseURLString: baseURLString)
            return .blockquote(content)

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

        case "div", "span", "aside", "details", "summary", "section", "header", "nav":
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

    private static func extractTextContent(from nodes: [FireRichTextNode]) -> String {
        nodes.map { node in
            switch node {
            case .text(let t): return t
            case .bold(let c), .italic(let c), .strikethrough(let c),
                 .paragraph(let c), .heading(_, let c), .blockquote(let c),
                 .listItem(let c): return extractTextContent(from: c)
            case .link(_, let c): return extractTextContent(from: c)
            case .code(let t): return t
            case .codeBlock(_, let t): return t
            case .mention(let u): return "@\(u)"
            case .lineBreak: return "\n"
            case .image: return ""
            }
        }.joined()
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
                let linkAttrs = textAttributes(for: context, overrideColor: context.accentColor)
                let linkText = NSMutableAttributedString()
                appendNodes(children, to: linkText, context: context)
                // Apply link attribute to entire range
                linkText.addAttributes([
                    .foregroundColor: context.accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: url,
                ], range: NSRange(location: 0, length: linkText.length))
                result.append(linkText)

            case .mention(let username):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: context.currentFont,
                    .foregroundColor: context.accentColor,
                ]
                result.append(NSAttributedString(string: "@\(username)", attributes: attrs))

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
                let paragraph = NSMutableParagraphStyle()
                paragraph.firstLineHeadIndent = 16
                paragraph.headIndent = 16

                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }

                let quoteResult = NSMutableAttributedString()
                appendNodes(children, to: quoteResult, context: context.indented())
                quoteResult.addAttributes([
                    .paragraphStyle: paragraph,
                    .foregroundColor: UIColor.secondaryLabel,
                ], range: NSRange(location: 0, length: quoteResult.length))
                // Add quote indicator
                let indicator = NSAttributedString(string: "┃ ", attributes: [
                    .foregroundColor: UIColor.separator,
                    .font: context.currentFont,
                ])
                result.append(indicator)
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
}
