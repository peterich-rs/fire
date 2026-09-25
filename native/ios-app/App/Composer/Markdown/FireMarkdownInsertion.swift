import Foundation

enum FireMarkdownFormatAction: CaseIterable, Identifiable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case codeBlock
    case quote
    case unorderedList
    case orderedList
    case link
    case image

    var id: Self { self }

    var title: String {
        switch self {
        case .bold:
            return "B"
        case .italic:
            return "I"
        case .strikethrough:
            return "S"
        case .inlineCode:
            return "<>"
        case .codeBlock:
            return "```"
        case .quote:
            return "Quote"
        case .unorderedList:
            return "UL"
        case .orderedList:
            return "OL"
        case .link:
            return "Link"
        case .image:
            return "Image"
        }
    }

    var systemImage: String? {
        switch self {
        case .bold, .italic, .strikethrough:
            return nil
        case .inlineCode:
            return "chevron.left.forwardslash.chevron.right"
        case .codeBlock:
            return "curlybraces"
        case .quote:
            return "text.quote"
        case .unorderedList:
            return "list.bullet"
        case .orderedList:
            return "list.number"
        case .link:
            return "link"
        case .image:
            return "photo"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .bold:
            return "加粗"
        case .italic:
            return "斜体"
        case .strikethrough:
            return "删除线"
        case .inlineCode:
            return "行内代码"
        case .codeBlock:
            return "代码块"
        case .quote:
            return "引用"
        case .unorderedList:
            return "项目列表"
        case .orderedList:
            return "编号列表"
        case .link:
            return "链接"
        case .image:
            return "图片标记"
        }
    }
}

extension FireMarkdownFormatAction {
    var rawTag: Int {
        switch self {
        case .bold: return 1
        case .italic: return 2
        case .strikethrough: return 3
        case .inlineCode: return 4
        case .codeBlock: return 5
        case .quote: return 6
        case .unorderedList: return 7
        case .orderedList: return 8
        case .link: return 9
        case .image: return 10
        }
    }

    init?(rawTag: Int) {
        guard let action = Self.allCases.first(where: { $0.rawTag == rawTag }) else {
            return nil
        }
        self = action
    }
}

struct FireMarkdownInsertionResult: Equatable {
    let text: String
    let selectedRange: NSRange
}

enum FireMarkdownInsertion {
    static func apply(
        _ action: FireMarkdownFormatAction,
        text: String,
        selectedRange: NSRange
    ) -> FireMarkdownInsertionResult {
        switch action {
        case .bold:
            return wrap(text: text, selectedRange: selectedRange, prefix: "**", suffix: "**", placeholder: "")
        case .italic:
            return wrap(text: text, selectedRange: selectedRange, prefix: "*", suffix: "*", placeholder: "")
        case .strikethrough:
            return wrap(text: text, selectedRange: selectedRange, prefix: "~~", suffix: "~~", placeholder: "")
        case .inlineCode:
            return wrap(text: text, selectedRange: selectedRange, prefix: "`", suffix: "`", placeholder: "")
        case .codeBlock:
            return codeBlock(text: text, selectedRange: selectedRange)
        case .quote:
            return prefixLines(text: text, selectedRange: selectedRange) { _ in "> " }
        case .unorderedList:
            return prefixLines(text: text, selectedRange: selectedRange) { _ in "- " }
        case .orderedList:
            return prefixLines(text: text, selectedRange: selectedRange) { index in "\(index + 1). " }
        case .link:
            return wrap(text: text, selectedRange: selectedRange, prefix: "[", suffix: "](url)", placeholder: "text")
        case .image:
            return wrap(text: text, selectedRange: selectedRange, prefix: "![", suffix: "](url)", placeholder: "alt")
        }
    }

    private static func wrap(
        text: String,
        selectedRange: NSRange,
        prefix: String,
        suffix: String,
        placeholder: String
    ) -> FireMarkdownInsertionResult {
        let source = text as NSString
        let safeRange = boundedRange(selectedRange, in: source)
        let selectedText = safeRange.length > 0 ? source.substring(with: safeRange) : placeholder
        let replacement = "\(prefix)\(selectedText)\(suffix)"
        let nextText = source.replacingCharacters(in: safeRange, with: replacement)
        let selectedLength = safeRange.length > 0
            ? safeRange.length
            : (placeholder as NSString).length
        return FireMarkdownInsertionResult(
            text: nextText,
            selectedRange: NSRange(
                location: safeRange.location + (prefix as NSString).length,
                length: selectedLength
            )
        )
    }

    private static func codeBlock(
        text: String,
        selectedRange: NSRange
    ) -> FireMarkdownInsertionResult {
        let source = text as NSString
        let safeRange = boundedRange(selectedRange, in: source)
        let selectedText = safeRange.length > 0 ? source.substring(with: safeRange) : ""
        let startsLine = safeRange.location == 0
            || source.substring(with: NSRange(location: safeRange.location - 1, length: 1)) == "\n"
        let endLocation = safeRange.location + safeRange.length
        let endsLine = endLocation >= source.length
            || source.substring(with: NSRange(location: endLocation, length: 1)) == "\n"
        let leadingBreak = startsLine ? "" : "\n"
        let trailingBreak = endsLine ? "" : "\n"
        let replacement = "\(leadingBreak)```\n\(selectedText)\n```\(trailingBreak)"
        let nextText = source.replacingCharacters(in: safeRange, with: replacement)
        let selectionLocation = safeRange.location
            + (leadingBreak as NSString).length
            + ("```\n" as NSString).length
        let selectionLength = safeRange.length > 0 ? (selectedText as NSString).length : 0
        return FireMarkdownInsertionResult(
            text: nextText,
            selectedRange: NSRange(location: selectionLocation, length: selectionLength)
        )
    }

    private static func prefixLines(
        text: String,
        selectedRange: NSRange,
        prefix: (Int) -> String
    ) -> FireMarkdownInsertionResult {
        let source = text as NSString
        let safeRange = boundedRange(selectedRange, in: source)
        if safeRange.length == 0 {
            let lineRange = source.lineRange(for: safeRange)
            let linePrefix = prefix(0)
            let nextText = source.replacingCharacters(
                in: NSRange(location: lineRange.location, length: 0),
                with: linePrefix
            )
            return FireMarkdownInsertionResult(
                text: nextText,
                selectedRange: NSRange(
                    location: safeRange.location + (linePrefix as NSString).length,
                    length: 0
                )
            )
        }

        let lineRange = source.lineRange(for: safeRange)
        let selectedLines = source.substring(with: lineRange)
        let preservesTrailingNewline = selectedLines.hasSuffix("\n")
        let body = preservesTrailingNewline ? String(selectedLines.dropLast()) : selectedLines
        let prefixedBody = body
            .components(separatedBy: "\n")
            .enumerated()
            .map { index, line in "\(prefix(index))\(line)" }
            .joined(separator: "\n")
        let replacement = prefixedBody + (preservesTrailingNewline ? "\n" : "")
        let nextText = source.replacingCharacters(in: lineRange, with: replacement)
        return FireMarkdownInsertionResult(
            text: nextText,
            selectedRange: NSRange(location: lineRange.location, length: (replacement as NSString).length)
        )
    }

    private static func boundedRange(_ range: NSRange, in source: NSString) -> NSRange {
        let location = min(max(range.location, 0), source.length)
        let length = min(max(range.length, 0), max(0, source.length - location))
        return NSRange(location: location, length: length)
    }
}
