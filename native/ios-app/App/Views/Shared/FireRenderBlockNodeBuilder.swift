import Foundation
import UIKit

enum FireRenderBlockNodeBuilder {
    static func build(document: RenderDocumentState?) -> FireRichTextContent {
        guard let document, !document.blocks.isEmpty else {
            return FireRichTextContent(
                nodes: [],
                plainText: document?.plainText ?? "",
                imageAttachments: []
            )
        }

        let tree = RenderBlockTree(blocks: document.blocks)
        let nodes = tree.root.map {
            mapChildren(of: $0, tree: tree)
        } ?? []
        return FireRichTextContent(
            nodes: nodes,
            plainText: document.plainText,
            imageAttachments: document.imageAttachments.compactMap { image in
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
        )
    }

    private struct RenderBlockTree {
        let root: RenderBlockState?
        private let childrenByParentID: [UInt32: [RenderBlockState]]

        init(blocks: [RenderBlockState]) {
            childrenByParentID = Dictionary(grouping: blocks.compactMap { block -> RenderBlockState? in
                block.parentId == nil ? nil : block
            }, by: { $0.parentId ?? 0 })
            root = blocks.first(where: { $0.parentId == nil && $0.kind == .document })
                ?? blocks.first(where: { $0.parentId == nil })
        }

        func children(of block: RenderBlockState) -> [RenderBlockState] {
            childrenByParentID[block.id] ?? []
        }
    }

    private static func mapChildren(
        of block: RenderBlockState,
        tree: RenderBlockTree
    ) -> [FireRichTextNode] {
        tree.children(of: block).flatMap { child in
            mapBlock(child, tree: tree)
        }
    }

    private static func mapBlock(
        _ block: RenderBlockState,
        tree: RenderBlockTree
    ) -> [FireRichTextNode] {
        let children = mapChildren(of: block, tree: tree)

        switch block.kind {
        case .document:
            return children
        case .text(let content):
            return [.text(content)]
        case .paragraph:
            return [.paragraph(children)]
        case .heading(let level):
            return [.heading(level: Int(level), children: children)]
        case .lineBreak:
            return [.lineBreak]
        case .bold:
            return [.bold(children)]
        case .italic:
            return [.italic(children)]
        case .strikethrough:
            return [.strikethrough(children)]
        case .inlineCode(let code):
            return [.code(code)]
        case .codeBlock(let language, let code):
            return [.codeBlock(language: language, code: code)]
        case .link(let url):
            return [.link(url: url, children: children)]
        case .mention(let username):
            return [.mention(username: username)]
        case .mentionGroup(let name, let url):
            return [.mentionGroup(name: name, url: url)]
        case .hashtag(let text, let url, let kind):
            return [.hashtag(text: text, url: url, kind: kind)]
        case .emoji(let url, let fallbackText, let onlyEmoji):
            return [.emoji(url: url, fallbackText: fallbackText, onlyEmoji: onlyEmoji)]
        case .image(let url, let alt, let width, let height):
            return [.image(
                src: url,
                alt: alt,
                width: width.map(CGFloat.init),
                height: height.map(CGFloat.init)
            )]
        case .blockquote:
            return [.blockquote(children)]
        case .quote(let author, let postNumber, let topicID):
            return [.quote(
                author: author,
                postNumber: postNumber,
                topicId: topicID,
                children: children
            )]
        case .list(let ordered):
            let items = tree.children(of: block).compactMap { child -> [FireRichTextNode]? in
                guard case .listItem = child.kind else { return nil }
                guard case let .some(.listItem(itemChildren)) = mapBlock(child, tree: tree).first else {
                    return nil
                }
                return itemChildren
            }
            return items.isEmpty ? children : [.list(ordered: ordered, items: items)]
        case .listItem:
            return [.listItem(children)]
        case .spoiler:
            return [.spoiler(children)]
        case .details:
            let summary = tree.children(of: block)
                .first(where: {
                    if case .detailsSummary = $0.kind { return true }
                    return false
                })
                .map { mapChildren(of: $0, tree: tree) } ?? []
            let body = tree.children(of: block)
                .filter {
                    if case .detailsSummary = $0.kind { return false }
                    return true
                }
                .flatMap { mapBlock($0, tree: tree) }
            return [.details(summary: summary, children: body)]
        case .detailsSummary:
            return children
        case .table(let text):
            return [.table(text)]
        case .onebox(let url, let title, let description):
            return [.onebox(url: url, title: title, description: description)]
        case .video(let url, let title):
            return [.video(url: url, title: title)]
        case .divider:
            return [.divider]
        case .unknown:
            return children
        }
    }
}
