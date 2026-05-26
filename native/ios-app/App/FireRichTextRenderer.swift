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

/// Parsed rich text content for a single post.
struct FireRichTextContent: Sendable {
    let nodes: [FireRichTextNode]
    let plainText: String
    let imageAttachments: [FireCookedImage]
}

// MARK: - Cooked HTML → Rich Text Parser

enum FireRichTextParser {
    /// Parse Discourse `cooked` HTML into structured rich text nodes.
    /// The HTML tree comes from the shared Rust parser backed by scraper/html5ever;
    /// this layer only adapts the shared AST to the iOS renderer model.
    static func parse(html: String, baseURLString: String) -> FireRichTextContent {
        guard !html.isEmpty else {
            return FireRichTextContent(nodes: [], plainText: "", imageAttachments: [])
        }

        let document = parseCookedHtml(rawHtml: html)
        let tree = CookedHtmlTree(nodes: document.nodes)
        let nodes = tree.root.map {
            mapChildren(of: $0, tree: tree, baseURLString: baseURLString)
        } ?? []
        return FireRichTextContent(
            nodes: nodes,
            plainText: plainText(from: nodes),
            imageAttachments: imageAttachments(from: document, tree: tree, baseURLString: baseURLString)
        )
    }

    private struct CookedHtmlTree {
        let root: CookedHtmlNodeState?
        private let nodesByID: [UInt32: CookedHtmlNodeState]
        private let childrenByParentID: [UInt32: [CookedHtmlNodeState]]

        init(nodes: [CookedHtmlNodeState]) {
            nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            childrenByParentID = Dictionary(grouping: nodes.compactMap { node -> CookedHtmlNodeState? in
                node.parentId == nil ? nil : node
            }, by: { $0.parentId ?? 0 })
            root = nodes.first(where: { $0.parentId == nil && $0.kind == .document })
                ?? nodes.first(where: { $0.parentId == nil })
        }

        func node(id: UInt32?) -> CookedHtmlNodeState? {
            guard let id else { return nil }
            return nodesByID[id]
        }

        func children(of node: CookedHtmlNodeState) -> [CookedHtmlNodeState] {
            childrenByParentID[node.id] ?? []
        }

        func nearestAncestor(
            of node: CookedHtmlNodeState,
            matching predicate: (CookedHtmlNodeState) -> Bool
        ) -> CookedHtmlNodeState? {
            var current = self.node(id: node.parentId)
            while let candidate = current {
                if predicate(candidate) {
                    return candidate
                }
                current = self.node(id: candidate.parentId)
            }
            return nil
        }
    }

    private static func mapChildren(
        of node: CookedHtmlNodeState,
        tree: CookedHtmlTree,
        baseURLString: String
    ) -> [FireRichTextNode] {
        tree.children(of: node).flatMap { child in
            mapNode(child, tree: tree, baseURLString: baseURLString)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func mapNode(
        _ node: CookedHtmlNodeState,
        tree: CookedHtmlTree,
        baseURLString: String
    ) -> [FireRichTextNode] {
        let children = mapChildren(of: node, tree: tree, baseURLString: baseURLString)
        let attrs = attributes(from: node)

        switch node.kind {
        case .document:
            return children
        case .text:
            return normalizedText(node.text).map { [.text($0)] } ?? []
        case .paragraph:
            return [.paragraph(children)]
        case .heading:
            return [.heading(level: Int(node.level ?? 2), children: children)]
        case .lineBreak:
            return [.lineBreak]
        case .strong:
            return [.bold(children)]
        case .emphasis:
            return [.italic(children)]
        case .strikethrough:
            return [.strikethrough(children)]
        case .code:
            return [.code(subtreeText(node, tree: tree))]
        case .codeBlock:
            return [.codeBlock(language: codeLanguage(in: node, tree: tree), code: subtreeText(node, tree: tree))]
        case .link:
            return mapLinkNode(node, children: children, attrs: attrs, baseURLString: baseURLString)
        case .mention:
            let username = extractTextContent(from: children, includingEmojiFallback: false)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanUsername = username.hasPrefix("@") ? String(username.dropFirst()) : username
            return cleanUsername.isEmpty ? children : [.mention(username: cleanUsername)]
        case .hashtag:
            let text = extractTextContent(from: children, includingEmojiFallback: false)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanText = text.hasPrefix("#") ? String(text.dropFirst()) : text
            let url = resolveURL(node.url ?? "", baseURLString: baseURLString)
            return cleanText.isEmpty ? children : [.hashtag(text: cleanText, url: url, kind: normalizedText(attrs["data-type"]))]
        case .image:
            guard let source = resolvedURLString(node.url, baseURLString: baseURLString), !isEmojiNode(node) else {
                return []
            }
            return [.image(
                src: source,
                alt: normalizedText(node.alt),
                width: numericAttribute("width", in: attrs),
                height: numericAttribute("height", in: attrs)
            )]
        case .emoji:
            guard let source = resolvedURLString(node.url, baseURLString: baseURLString) else {
                let fallback = emojiFallbackText(from: attrs, resolvedURLString: "")
                return fallback.isEmpty ? [] : [.text(fallback)]
            }
            return [.emoji(
                url: source,
                fallbackText: emojiFallbackText(from: attrs, resolvedURLString: source),
                onlyEmoji: classNames(from: attrs["class"]).contains("only-emoji")
            )]
        case .blockquote:
            return [.blockquote(children)]
        case .discourseQuote:
            return [.quote(
                author: normalizedText(attrs["data-username"] ?? node.title),
                postNumber: attrs["data-post"].flatMap(UInt32.init),
                topicId: attrs["data-topic"].flatMap(UInt64.init),
                children: normalizeQuotedChildren(children)
            )]
        case .list:
            let items = tree.children(of: node).compactMap { child -> [FireRichTextNode]? in
                guard child.kind == .listItem else { return nil }
                return mapChildren(of: child, tree: tree, baseURLString: baseURLString)
            }
            return items.isEmpty ? children : [.list(ordered: node.ordered == true, items: items)]
        case .listItem:
            return [.listItem(children)]
        case .spoiler:
            return [.spoiler(children)]
        case .details:
            let parts = detailsParts(from: children)
            return [.details(summary: parts.summary, children: parts.body)]
        case .table:
            return [.table(tablePlainText(from: node, tree: tree))]
        case .tableRow, .tableCell:
            return children
        case .onebox:
            return [.onebox(
                url: resolvedURLString(node.url, baseURLString: baseURLString),
                title: normalizedText(node.title) ?? normalizedText(subtreeText(node, tree: tree)),
                description: nil
            )]
        case .iframe:
            guard let url = resolvedURLString(node.url, baseURLString: baseURLString) else {
                return children
            }
            return [.video(url: url, title: normalizedText(node.title))]
        case .attachment:
            let url = resolveURL(node.url ?? "", baseURLString: baseURLString)
            return url.isEmpty ? children : [.link(url: url, children: children)]
        case .unknown:
            return children
        }
    }

    private static func mapLinkNode(
        _ node: CookedHtmlNodeState,
        children: [FireRichTextNode],
        attrs: [String: String],
        baseURLString: String
    ) -> [FireRichTextNode] {
        let url = resolveURL(node.url ?? "", baseURLString: baseURLString)
        let classes = classNames(from: attrs["class"])

        if classes.contains("mention-group") {
            let groupName = extractTextContent(from: children, includingEmojiFallback: false)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanName = groupName.hasPrefix("@") ? String(groupName.dropFirst()) : groupName
            return cleanName.isEmpty ? children : [.mentionGroup(name: cleanName, url: url)]
        }
        if classes.contains("mention") {
            let username = extractTextContent(from: children, includingEmojiFallback: false)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanUsername = username.hasPrefix("@") ? String(username.dropFirst()) : username
            return cleanUsername.isEmpty ? children : [.mention(username: cleanUsername)]
        }
        if classes.contains("hashtag") || classes.contains("hashtag-cooked") {
            let hashtag = extractTextContent(from: children, includingEmojiFallback: false)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanHashtag = hashtag.hasPrefix("#") ? String(hashtag.dropFirst()) : hashtag
            return cleanHashtag.isEmpty ? children : [.hashtag(
                text: cleanHashtag,
                url: url,
                kind: normalizedText(attrs["data-type"])
            )]
        }

        if shouldSuppressLinkForInlineImage(urlString: url, classNames: classes, children: children) {
            return children
        }
        return [.link(url: url, children: children)]
    }

    private static func imageAttachments(
        from document: CookedHtmlDocumentState,
        tree: CookedHtmlTree,
        baseURLString: String
    ) -> [FireCookedImage] {
        var images: [FireCookedImage] = []
        var seenURLs: Set<String> = []

        for node in document.nodes where node.kind == .image && !isEmojiNode(node) {
            let attrs = attributes(from: node)
            let preferredSource = tree.nearestAncestor(of: node) { ancestor in
                ancestor.kind == .link || ancestor.kind == .attachment
            }?.url
            let rawSource = normalizedText(preferredSource) ?? normalizedText(node.url)
            guard let sourceURL = rawSource.flatMap({ resolvedAssetURL(from: $0, baseURLString: baseURLString) }) else {
                continue
            }

            let absoluteURL = sourceURL.absoluteString
            if absoluteURL.contains("/images/emoji/") || seenURLs.contains(absoluteURL) {
                continue
            }

            seenURLs.insert(absoluteURL)
            images.append(FireCookedImage(
                url: sourceURL,
                altText: normalizedText(node.alt),
                width: numericAttribute("width", in: attrs),
                height: numericAttribute("height", in: attrs)
            ))
        }

        return images
    }

    private static func plainText(from nodes: [FireRichTextNode]) -> String {
        var builder = PlainTextBuilder()
        builder.append(nodes)
        return builder.text
    }

    private static func attributes(from node: CookedHtmlNodeState) -> [String: String] {
        Dictionary(uniqueKeysWithValues: node.attributes.map { ($0.name.lowercased(), $0.value) })
    }

    private static func isEmojiNode(_ node: CookedHtmlNodeState) -> Bool {
        if node.kind == .emoji {
            return true
        }
        let attrs = attributes(from: node)
        if classNames(from: attrs["class"]).contains("emoji") {
            return true
        }
        return node.url?.contains("/images/emoji/") == true
    }

    private static func numericAttribute(_ name: String, in attrs: [String: String]) -> CGFloat? {
        attrs[name].flatMap(Double.init).map { CGFloat($0) }
    }

    private static func resolvedURLString(_ rawValue: String?, baseURLString: String) -> String? {
        let resolved = resolveURL(rawValue ?? "", baseURLString: baseURLString)
        return resolved.isEmpty ? nil : resolved
    }

    private static func resolvedAssetURL(from rawValue: String, baseURLString: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }

        if let absoluteURL = URL(string: trimmed), absoluteURL.scheme != nil {
            return absoluteURL
        }

        return URL(string: trimmed, relativeTo: URL(string: baseURLString))?.absoluteURL
    }

    private static func codeLanguage(in node: CookedHtmlNodeState, tree: CookedHtmlTree) -> String? {
        let classes = classNames(from: attributes(from: node)["class"])
        for className in classes {
            if className.hasPrefix("language-") {
                return String(className.dropFirst("language-".count))
            }
            if className.hasPrefix("lang-") {
                return String(className.dropFirst("lang-".count))
            }
        }

        for child in tree.children(of: node) {
            if let language = codeLanguage(in: child, tree: tree) {
                return language
            }
        }
        return nil
    }

    private static func subtreeText(_ node: CookedHtmlNodeState, tree: CookedHtmlTree) -> String {
        var builder = PlainTextBuilder()
        appendSubtreeText(node, tree: tree, to: &builder)
        return builder.text
    }

    private static func appendSubtreeText(
        _ node: CookedHtmlNodeState,
        tree: CookedHtmlTree,
        to builder: inout PlainTextBuilder
    ) {
        switch node.kind {
        case .text:
            builder.appendInline(node.text ?? "")
        case .lineBreak:
            builder.ensureLineBreak()
        case .image:
            if isEmojiNode(node) {
                builder.appendInline(emojiFallbackText(from: attributes(from: node), resolvedURLString: node.url ?? ""))
            }
        case .emoji:
            builder.appendInline(emojiFallbackText(from: attributes(from: node), resolvedURLString: node.url ?? ""))
        case .tableCell:
            tree.children(of: node).forEach { appendSubtreeText($0, tree: tree, to: &builder) }
            builder.appendInline(" ")
        case .tableRow, .listItem:
            tree.children(of: node).forEach { appendSubtreeText($0, tree: tree, to: &builder) }
            builder.ensureLineBreak()
        default:
            tree.children(of: node).forEach { appendSubtreeText($0, tree: tree, to: &builder) }
        }
    }

    private static func detailsParts(
        from children: [FireRichTextNode]
    ) -> (summary: [FireRichTextNode], body: [FireRichTextNode]) {
        var summary: [FireRichTextNode] = []
        var body: [FireRichTextNode] = []
        var isReadingSummary = true

        for child in children {
            if isReadingSummary && isInlineDetailsSummaryNode(child) {
                summary.append(child)
            } else {
                isReadingSummary = false
                body.append(child)
            }
        }

        return (summary.isEmpty ? [.text("Details")] : summary, body)
    }

    private static func isInlineDetailsSummaryNode(_ node: FireRichTextNode) -> Bool {
        switch node {
        case .text(let value):
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .bold, .italic, .strikethrough, .code, .link, .mention, .mentionGroup, .hashtag, .emoji:
            return true
        default:
            return false
        }
    }

    private static func tablePlainText(from node: CookedHtmlNodeState, tree: CookedHtmlTree) -> String {
        let rows = tree.children(of: node).filter { $0.kind == .tableRow }
        guard !rows.isEmpty else {
            return subtreeText(node, tree: tree)
        }

        return rows.compactMap { row in
            let cells = tree.children(of: row).filter { $0.kind == .tableCell }
            let text = cells
                .map { subtreeText($0, tree: tree).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
            return text.isEmpty ? nil : text
        }.joined(separator: "\n")
    }

    private struct PlainTextBuilder {
        private var storage = ""

        var text: String {
            storage.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        mutating func append(_ nodes: [FireRichTextNode]) {
            nodes.forEach { append($0) }
        }

        // swiftlint:disable:next cyclomatic_complexity
        mutating func append(_ node: FireRichTextNode) {
            switch node {
            case .text(let value), .code(let value):
                appendInline(value)
            case .bold(let children), .italic(let children), .strikethrough(let children),
                 .link(_, let children), .blockquote(let children), .quote(_, _, _, let children),
                 .spoiler(let children), .paragraph(let children), .heading(_, let children),
                 .listItem(let children):
                append(children)
            case .codeBlock(_, let code), .table(let code):
                ensureBlockBoundary()
                appendPreformatted(code)
                ensureBlockBoundary()
            case .mention(let username):
                appendInline("@\(username)")
            case .mentionGroup(let name, _):
                appendInline("@\(name)")
            case .hashtag(let text, _, _):
                appendInline("#\(text)")
            case .emoji(_, let fallbackText, _):
                appendInline(fallbackText)
            case .onebox(let url, let title, let description):
                ensureBlockBoundary()
                [title, description, url].compactMap { $0 }.forEach { appendInline($0); ensureLineBreak() }
                ensureBlockBoundary()
            case .list(let ordered, let items):
                ensureBlockBoundary()
                for (index, item) in items.enumerated() {
                    appendInline(ordered ? "\(index + 1)." : "-")
                    append(item)
                    ensureLineBreak()
                }
                ensureBlockBoundary()
            case .details(let summary, let children):
                ensureBlockBoundary()
                append(summary)
                ensureLineBreak()
                append(children)
                ensureBlockBoundary()
            case .video(let url, let title):
                appendInline(title ?? url)
            case .divider:
                ensureBlockBoundary()
            case .lineBreak:
                ensureLineBreak()
            case .image:
                break
            }
        }

        mutating func appendInline(_ rawValue: String) {
            let value = rawValue.replacingOccurrences(of: "\u{a0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return
            }
            if shouldInsertInlineSeparator(before: value) {
                storage.append(" ")
            }
            storage.append(value)
        }

        mutating func appendPreformatted(_ rawValue: String) {
            let value = rawValue.trimmingCharacters(in: .newlines)
            guard !value.isEmpty else {
                return
            }
            storage.append(value)
        }

        mutating func ensureLineBreak() {
            trimTrailingSpaces()
            if !storage.isEmpty && !storage.hasSuffix("\n") {
                storage.append("\n")
            }
        }

        mutating func ensureBlockBoundary() {
            trimTrailingSpaces()
            guard !storage.isEmpty else {
                return
            }
            let trailingNewlineCount = storage.reversed().prefix { $0 == "\n" }.count
            for _ in trailingNewlineCount..<2 {
                storage.append("\n")
            }
        }

        private mutating func trimTrailingSpaces() {
            while storage.last == " " || storage.last == "\t" {
                storage.removeLast()
            }
        }

        private func shouldInsertInlineSeparator(before nextText: String) -> Bool {
            guard let previous = storage.last, !previous.isWhitespace else {
                return false
            }
            guard let next = nextText.first, !next.isWhitespace, !Self.isClosingPunctuation(next) else {
                return false
            }
            if Self.isCJK(previous) && Self.isCJK(next) {
                return false
            }
            return Self.isWordBoundary(previous) && Self.isWordBoundary(next)
        }

        private static func isWordBoundary(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || "@#_)]}".contains(character)
        }

        private static func isClosingPunctuation(_ character: Character) -> Bool {
            ".,!?:;)]}%。，！？：；、".contains(character)
        }

        private static func isCJK(_ character: Character) -> Bool {
            character.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                    return true
                default:
                    return false
                }
            }
        }
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
            case .mentionGroup(let name, _): return "@\(name)"
            case .hashtag(let text, _, _): return "#\(text)"
            case .emoji(_, let fallbackText, _): return includingEmojiFallback ? fallbackText : ""
            case .onebox(let url, let title, let description):
                return [title, description, url].compactMap { $0 }.joined(separator: "\n")
            case .list(_, let items):
                return items.map {
                    extractTextContent(from: $0, includingEmojiFallback: includingEmojiFallback)
                }.joined(separator: "\n")
            case .spoiler(let c):
                return extractTextContent(from: c, includingEmojiFallback: includingEmojiFallback)
            case .details(let summary, let c):
                return (
                    extractTextContent(from: summary, includingEmojiFallback: includingEmojiFallback)
                    + "\n"
                    + extractTextContent(from: c, includingEmojiFallback: includingEmojiFallback)
                )
            case .table(let text): return text
            case .video(let url, let title): return title ?? url
            case .divider: return "\n"
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

            case .onebox(let url, let title, let description):
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                result.append(oneboxAttributedString(
                    url: url,
                    title: title,
                    description: description,
                    context: context
                ))
                result.append(NSAttributedString(string: "\n"))

            case .list(let ordered, let items):
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                for (index, item) in items.enumerated() {
                    if index > 0 {
                        result.append(NSAttributedString(string: "\n"))
                    }
                    let prefix = ordered ? "\(index + 1). " : " • "
                    result.append(NSAttributedString(string: prefix, attributes: textAttributes(for: context)))
                    appendNodes(item, to: result, context: context)
                }

            case .listItem(let children):
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                let bullet = NSAttributedString(string: " • ", attributes: textAttributes(for: context))
                result.append(bullet)
                appendNodes(children, to: result, context: context)

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
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                let summaryResult = NSMutableAttributedString(
                    string: "▾ ",
                    attributes: textAttributes(for: context)
                )
                appendNodes(summary, to: summaryResult, context: context.withBold())
                result.append(summaryResult)
                if !children.isEmpty {
                    result.append(NSAttributedString(string: "\n"))
                    appendNodes(children, to: result, context: context.indented())
                }

            case .table(let text):
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                var attrs = textAttributes(for: context)
                attrs[.font] = UIFont.monospacedSystemFont(
                    ofSize: context.baseFont.pointSize - 1,
                    weight: .regular
                )
                attrs[.backgroundColor] = context.codeBackgroundColor
                result.append(NSAttributedString(string: text, attributes: attrs))
                result.append(NSAttributedString(string: "\n"))

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
                if result.length > 0 && !result.string.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                result.append(NSAttributedString(
                    string: "----------",
                    attributes: textAttributes(for: context.withTextColor(.separator))
                ))
                result.append(NSAttributedString(string: "\n"))

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

/// Custom UITextView that sizes itself to content.
final class FireRichTextUIView: UITextView {
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
        setNeedsLayout()
    }
}
