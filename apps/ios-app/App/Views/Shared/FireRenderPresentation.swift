import Foundation
import UIKit

/// Host mapping for Rust `RenderDocumentHandle` / UI plan.
///
/// Platforms only turn precomputed segments into native nodes. They do not
/// parse cooked HTML or walk a block tree.
enum FireRenderPresentation {
    static func checksum(_ handle: RenderDocumentHandle) -> UInt64 {
        handle.checksum()
    }

    static func images(from handle: RenderDocumentHandle) -> [FireCookedImage] {
        handle.imageAttachments().compactMap(cookedImage(from:))
    }

    static func richNodes(from handle: RenderDocumentHandle) -> [FireRichTextNode] {
        segments(from: handle).flatMap { segment -> [FireRichTextNode] in
            switch segment {
            case let .rich(nodes):
                return nodes
            case .image, .onebox:
                return []
            }
        }
    }

    static func segments(from handle: RenderDocumentHandle) -> [MappedUiSegment] {
        let count = handle.segmentCount()
        return (UInt32(0)..<count).compactMap { index in
            handle.segment(index: index).map(mapSegment)
        }
    }

    static func cookedImage(from image: RenderImageAttachmentState) -> FireCookedImage? {
        guard let url = URL(string: image.url) else {
            return nil
        }
        return FireCookedImage(
            url: url,
            altText: image.altText,
            width: image.width.map(CGFloat.init),
            height: image.height.map(CGFloat.init)
        )
    }

    enum MappedUiSegment {
        case rich([FireRichTextNode])
        case image(FireCookedImage)
        case onebox(FireTopicOneboxCard)
    }

    static func mapSegment(_ segment: RenderUiSegmentState) -> MappedUiSegment {
        switch segment {
        case let .rich(nodes):
            return .rich(nodes.map(mapNode))
        case let .image(image):
            let cooked = cookedImage(from: image) ?? FireCookedImage(
                url: URL(string: image.url) ?? URL(string: "about:blank")!,
                altText: image.altText,
                width: image.width.map(CGFloat.init),
                height: image.height.map(CGFloat.init)
            )
            return .image(cooked)
        case let .onebox(card):
            return .onebox(oneboxCard(from: card))
        }
    }

    static func oneboxCard(from card: RenderOneboxCardState) -> FireTopicOneboxCard {
        FireTopicOneboxCard(
            url: card.url,
            title: card.title,
            description: card.description,
            sourceName: card.sourceName,
            iconURL: card.iconUrl.flatMap(URL.init(string:)),
            thumbnailURL: card.thumbnailUrl.flatMap(URL.init(string:)),
            thumbnailWidth: card.thumbnailWidth.map(CGFloat.init),
            thumbnailHeight: card.thumbnailHeight.map(CGFloat.init)
        )
    }

    static func mapNode(_ node: RenderRichNodeState) -> FireRichTextNode {
        switch node {
        case let .text(content):
            return .text(content)
        case let .bold(children):
            return .bold(children.map(mapNode))
        case let .italic(children):
            return .italic(children.map(mapNode))
        case let .strikethrough(children):
            return .strikethrough(children.map(mapNode))
        case let .code(code):
            return .code(code)
        case let .codeBlock(language, code):
            return .codeBlock(language: language, code: code)
        case let .link(url, children):
            return .link(url: url, children: children.map(mapNode))
        case let .mention(username):
            return .mention(username: username)
        case let .mentionGroup(name, url):
            return .mentionGroup(name: name, url: url)
        case let .hashtag(text, url, kind):
            return .hashtag(text: text, url: url, kind: kind)
        case let .emoji(url, fallbackText, onlyEmoji):
            return .emoji(url: url, fallbackText: fallbackText, onlyEmoji: onlyEmoji)
        case let .heading(level, children):
            return .heading(level: Int(level), children: children.map(mapNode))
        case let .blockquote(children):
            return .blockquote(children.map(mapNode))
        case let .quote(author, postNumber, topicId, children):
            return .quote(
                author: author,
                postNumber: postNumber,
                topicId: topicId,
                children: children.map(mapNode)
            )
        case let .listNode(ordered, items):
            return .list(ordered: ordered, items: items.map { $0.map(mapNode) })
        case let .listItem(children):
            return .listItem(children.map(mapNode))
        case let .spoiler(children):
            return .spoiler(children.map(mapNode))
        case let .details(summary, children):
            return .details(summary: summary.map(mapNode), children: children.map(mapNode))
        case let .table(text):
            return .table(text)
        case let .video(url, title):
            return .video(url: url, title: title)
        case .divider:
            return .divider
        case .lineBreak:
            return .lineBreak
        case let .paragraph(children):
            return .paragraph(children.map(mapNode))
        case let .image(url, alt, width, height):
            return .image(
                src: url,
                alt: alt,
                width: width.map(CGFloat.init),
                height: height.map(CGFloat.init)
            )
        case let .onebox(card):
            return .onebox(
                url: card.url,
                title: card.title,
                description: card.description,
                sourceName: card.sourceName,
                iconURL: card.iconUrl,
                thumbnailURL: card.thumbnailUrl,
                thumbnailWidth: card.thumbnailWidth,
                thumbnailHeight: card.thumbnailHeight
            )
        }
    }
}
