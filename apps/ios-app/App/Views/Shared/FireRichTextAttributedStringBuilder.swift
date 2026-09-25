import UIKit


enum FireRichTextAttributedStringBuilder {
    /// Convert parsed nodes into an NSAttributedString suitable for display.
    /// Defaults use Fire theme ink tokens (not bare `UIColor.label`) so Texture
    /// post cells share the same adaptive palette as the rest of the app.
    static func build(
        from nodes: [FireRichTextNode],
        baseFont: UIFont = .preferredFont(forTextStyle: .subheadline),
        textColor: UIColor = FireTheme.uiInk,
        accentColor: UIColor = FireTheme.uiAccent,
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

    struct RenderContext {
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
    static func appendNodes(
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
                ensureBlockBoundary(result)

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
                ensureBlockBoundary(result)

            case .onebox(
                let url,
                let title,
                let description,
                let sourceName,
                _,
                _,
                _,
                _
            ):
                ensureBlockBoundary(result)
                result.append(oneboxAttributedString(
                    url: url,
                    title: title,
                    description: description,
                    sourceName: sourceName,
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
                        .foregroundColor: FireTheme.uiSubtleInk,
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
                // Thin hairline separator (avoid dashed ASCII which reads noisy).
                let dividerStyle = NSMutableParagraphStyle()
                dividerStyle.paragraphSpacingBefore = 10
                dividerStyle.paragraphSpacing = 10
                dividerStyle.maximumLineHeight = 1
                dividerStyle.minimumLineHeight = 1
                result.append(NSAttributedString(
                    string: "\u{00A0}",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 1),
                        .foregroundColor: UIColor.clear,
                        .backgroundColor: UIColor.separator.withAlphaComponent(0.55),
                        .paragraphStyle: dividerStyle,
                    ]
                ))

            case .lineBreak:
                result.append(NSAttributedString(string: "\n"))

            case .paragraph(let children):
                let start = result.length
                ensureBlockBoundary(result)
                appendNodes(children, to: result, context: context)
                // Slightly airier block rhythm closer to Discourse web spacing.
                if result.length > start {
                    let style = NSMutableParagraphStyle()
                    style.paragraphSpacing = 8
                    style.paragraphSpacingBefore = 2
                    style.lineSpacing = 2
                    style.lineBreakMode = .byWordWrapping
                    result.addAttribute(
                        .paragraphStyle,
                        value: style,
                        range: NSRange(location: start, length: result.length - start)
                    )
                }

            case .image:
                break // Handled separately via imageAttachments
            }
        }
    }


    /// Ensures the next block starts after a single blank-line boundary.
    static func ensureBlockBoundary(_ result: NSMutableAttributedString) {
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
    static func ensureLineBreak(_ result: NSMutableAttributedString) {
        trimTrailingSpaces(result)
        guard result.length > 0 else { return }
        let text = result.string as NSString
        let newlineChar: unichar = 10
        if text.length > 0 && text.character(at: text.length - 1) != newlineChar {
            result.append(NSAttributedString(string: "\n"))
        }
    }

    /// Removes trailing space and tab characters from the attributed string.
    static func trimTrailingSpaces(_ result: NSMutableAttributedString) {
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

}
