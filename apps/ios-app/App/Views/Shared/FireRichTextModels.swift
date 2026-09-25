import UIKit

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
    case onebox(
        url: String?,
        title: String?,
        description: String?,
        sourceName: String?,
        iconURL: String?,
        thumbnailURL: String?,
        thumbnailWidth: UInt32?,
        thumbnailHeight: UInt32?
    )
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
