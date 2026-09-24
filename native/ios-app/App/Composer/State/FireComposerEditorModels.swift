import Foundation

struct FireComposerMentionContext: Equatable {
    let replacementRange: NSRange
    let term: String
}

struct FireComposerMarkdownImage: Identifiable, Hashable {
    let urlString: String
    let altText: String?

    var id: String { urlString }
}
