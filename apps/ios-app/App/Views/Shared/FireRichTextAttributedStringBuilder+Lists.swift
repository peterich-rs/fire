import UIKit

extension FireRichTextAttributedStringBuilder {
    static func appendListItem(
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

    static func appendListItemContent(
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

    static func listParagraphStyle(marker: String, context: RenderContext) -> NSParagraphStyle {
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
}
