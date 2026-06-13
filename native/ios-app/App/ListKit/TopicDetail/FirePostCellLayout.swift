import Foundation
import UIKit

struct FirePostLayoutTraitSignature: Hashable, Sendable {
    let contentWidthPixels: Int
    let contentSizeCategory: String
}

struct FirePostCellLayoutKey: Hashable, Sendable {
    let postID: UInt64
    let depth: Int
    let showsThreadLine: Bool
    let showsDivider: Bool
    let replyTargetPostNumber: UInt32?
    let replyContext: String?
    let textContentID: String
    let imageSignature: [String]
    let pollSignature: [String]
    let boostSignature: [String]
    let hasReactions: Bool
    let replyShortcutCount: UInt32?
    let textExpansionState: FirePostTextExpansionState
    let acceptedAnswer: Bool
    let hasAuthorMetadata: Bool
    let trait: FirePostLayoutTraitSignature

    init(
        postID: UInt64,
        depth: Int,
        showsThreadLine: Bool,
        showsDivider: Bool,
        replyTargetPostNumber: UInt32?,
        replyContext: String?,
        textContentID: String,
        imageSignature: [String],
        pollSignature: [String],
        boostSignature: [String],
        hasReactions: Bool,
        replyShortcutCount: UInt32? = nil,
        textExpansionState: FirePostTextExpansionState,
        acceptedAnswer: Bool,
        hasAuthorMetadata: Bool,
        trait: FirePostLayoutTraitSignature
    ) {
        self.postID = postID
        self.depth = depth
        self.showsThreadLine = showsThreadLine
        self.showsDivider = showsDivider
        self.replyTargetPostNumber = replyTargetPostNumber
        self.replyContext = replyContext
        self.textContentID = textContentID
        self.imageSignature = imageSignature
        self.pollSignature = pollSignature
        self.boostSignature = boostSignature
        self.hasReactions = hasReactions
        self.replyShortcutCount = replyShortcutCount
        self.textExpansionState = textExpansionState
        self.acceptedAnswer = acceptedAnswer
        self.hasAuthorMetadata = hasAuthorMetadata
        self.trait = trait
    }
}

struct FirePostCellLayout: Equatable, Sendable {
    let key: FirePostCellLayoutKey
    let totalHeight: CGFloat
    let avatarFrame: CGRect
    let threadLineFrame: CGRect?
    let metaFrame: CGRect
    let textFrame: CGRect?
    let textContainerSize: CGSize
    let textExpansionFrame: CGRect?
    let imageFrames: [CGRect]
    let pollFrames: [CGRect]
    let boostFrames: [CGRect]
    let replyShortcutFrame: CGRect?
    let reactionsFrame: CGRect?
    let menuFrame: CGRect?
    let dividerFrame: CGRect?
}

enum FirePostReactionDisplayPolicy {
    static let replyVisibleReactionLimit = 3
    static let wrappedReactionMaxLines = 2

    static func visibleReactions(
        from reactions: [TopicReactionState],
        depth: Int
    ) -> [TopicReactionState] {
        guard depth > 0 else {
            return reactions
        }
        return Array(reactions.prefix(replyVisibleReactionLimit))
    }

    static func allowsWrapping(depth: Int) -> Bool {
        depth == 0
    }
}

enum FirePostBoostDisplay {
    static let bodyBarrageVisibleLineLimit = 5

    static func usesBodyBarrage(
        depth: Int,
        textExpansionState: FirePostTextExpansionState,
        hasBodyTextTarget: Bool
    ) -> Bool {
        hasBodyTextTarget && depth == 0 && !textExpansionState.isCollapsed
    }

    static func fixedDisplayLines(
        for boosts: [TopicPostBoostState],
        depth: Int,
        textExpansionState: FirePostTextExpansionState,
        hasBodyTextTarget: Bool
    ) -> [String] {
        guard !usesBodyBarrage(
            depth: depth,
            textExpansionState: textExpansionState,
            hasBodyTextTarget: hasBodyTextTarget
        ) else {
            return []
        }
        return boosts.map(displayLine(for:))
    }

    static func bodyBarrageLines(for boosts: [TopicPostBoostState]) -> [String] {
        Array(boosts.compactMap { strippedDisplayText(for: $0) }.prefix(bodyBarrageVisibleLineLimit))
    }

    static func bodyBarrageBoosts(for boosts: [TopicPostBoostState]) -> [TopicPostBoostState] {
        Array(boosts.filter { strippedDisplayText(for: $0) != nil }.prefix(bodyBarrageVisibleLineLimit))
    }

    static func bodyBarrageBatchSignature(
        postID: UInt64,
        boosts: [TopicPostBoostState]
    ) -> String {
        let boostTokens = boosts.compactMap { boost -> String? in
            guard let text = strippedDisplayText(for: boost) else { return nil }
            return [
                String(boost.id),
                text,
            ].joined(separator: "\u{1E}")
        }
        .prefix(bodyBarrageVisibleLineLimit)
        .joined(separator: "\u{1D}")
        guard !boostTokens.isEmpty else { return "" }
        return [String(postID), boostTokens].joined(separator: "\u{1F}")
    }

    static func displayLine(for boost: TopicPostBoostState) -> String {
        strippedDisplayText(for: boost) ?? ""
    }

    static func contentSignature(for boost: TopicPostBoostState) -> String {
        [
            String(boost.id),
            boost.displayText,
            boost.cooked,
            boost.renderDocument?.plainText ?? "",
        ].joined(separator: "\u{1E}")
    }

    static func displayContent(
        for boost: TopicPostBoostState,
        baseFont: UIFont = .preferredFont(forTextStyle: .caption1),
        textColor: UIColor = .label,
        accentColor: UIColor = .systemBlue
    ) -> NSAttributedString {
        if let content = richTextContent(for: boost, baseFont: baseFont, textColor: textColor, accentColor: accentColor),
           content.length > 0 {
            return content
        }
        if let text = strippedDisplayText(for: boost) {
            return NSAttributedString(
                string: text,
                attributes: [.font: baseFont, .foregroundColor: textColor]
            )
        }
        return NSAttributedString()
    }

    static func contentToken(for boosts: [TopicPostBoostState]) -> String {
        boosts.map { boost in
            [
                String(boost.id),
                boost.user.username,
                boost.user.name ?? "",
                boost.displayText,
                boost.cooked,
                String(boost.canDelete),
                String(boost.canFlag),
            ].joined(separator: "\u{1E}")
        }.joined(separator: "\u{1D}")
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func strippedDisplayText(for boost: TopicPostBoostState) -> String? {
        guard var text = cleaned(boost.displayText) else { return nil }
        let candidates = leadingAttributionCandidates(for: boost)
        for candidate in candidates {
            if text.range(of: candidate, options: [.caseInsensitive, .anchored]) != nil {
                text.removeFirst(candidate.count)
                return cleaned(text)
            }
        }
        guard let colonIndex = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return cleaned(text)
        }
        let prefix = text[..<colonIndex]
        guard prefix.count > 1,
              prefix.count <= 40,
              prefix.first == "@",
              prefix.dropFirst().allSatisfy({ !$0.isWhitespace }) else {
            return cleaned(text)
        }
        text.removeSubrange(...colonIndex)
        return cleaned(text)
    }

    private static func leadingAttributionCandidates(for boost: TopicPostBoostState) -> [String] {
        [
            cleaned(boost.user.username).map { "@\($0):" },
            cleaned(boost.user.username).map { "\($0):" },
            cleaned(boost.user.name).map { "\($0):" },
            cleaned(boost.user.username).map { "@\($0)：" },
            cleaned(boost.user.username).map { "\($0)：" },
            cleaned(boost.user.name).map { "\($0)：" },
        ].compactMap { $0 }
    }

    private static func richTextContent(
        for boost: TopicPostBoostState,
        baseFont: UIFont,
        textColor: UIColor,
        accentColor: UIColor
    ) -> NSAttributedString? {
        guard let document = boost.renderDocument else {
            return nil
        }
        let content = FireRenderBlockNodeBuilder.build(document: document)
        guard !content.nodes.isEmpty else {
            return nil
        }
        let attributedText = FireRichTextAttributedStringBuilder.build(
            from: content.nodes,
            baseFont: baseFont,
            textColor: textColor,
            accentColor: accentColor
        )
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        trimWhitespaceAndNewlines(mutable)
        stripLeadingAttribution(mutable, boost: boost)
        trimWhitespaceAndNewlines(mutable)
        return mutable.length > 0 ? mutable : nil
    }

    private static func trimWhitespaceAndNewlines(_ attributedText: NSMutableAttributedString) {
        while attributedText.length > 0 {
            let scalar = attributedText.string.unicodeScalars[attributedText.string.unicodeScalars.startIndex]
            guard CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
            attributedText.deleteCharacters(in: NSRange(location: 0, length: 1))
        }
        while attributedText.length > 0 {
            let string = attributedText.string
            let scalar = string.unicodeScalars[string.unicodeScalars.index(before: string.unicodeScalars.endIndex)]
            guard CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
            attributedText.deleteCharacters(in: NSRange(location: attributedText.length - 1, length: 1))
        }
    }

    private static func stripLeadingAttribution(
        _ attributedText: NSMutableAttributedString,
        boost: TopicPostBoostState
    ) {
        let string = attributedText.string
        guard !string.isEmpty else { return }

        let candidates = leadingAttributionCandidates(for: boost)

        for candidate in candidates {
            if string.range(
                of: candidate,
                options: [.caseInsensitive, .anchored]
            ) != nil {
                deleteLeadingCharacters(candidate.count, from: attributedText)
                trimWhitespaceAndNewlines(attributedText)
                return
            }
        }

        guard string.first == "@",
              let colonIndex = string.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return
        }
        let prefix = string[..<colonIndex]
        guard prefix.count > 1,
              prefix.count <= 40,
              prefix.dropFirst().allSatisfy({ !$0.isWhitespace }) else {
            return
        }
        deleteLeadingCharacters(prefix.count + 1, from: attributedText)
        trimWhitespaceAndNewlines(attributedText)
    }

    private static func deleteLeadingCharacters(
        _ characterCount: Int,
        from attributedText: NSMutableAttributedString
    ) {
        guard characterCount > 0 else { return }
        let prefix = String(attributedText.string.prefix(characterCount))
        attributedText.deleteCharacters(in: NSRange(location: 0, length: (prefix as NSString).length))
    }
}

extension FireTopicPostRenderContent {
    var hasBoostBarrageTextTarget: Bool {
        if let attributedText, attributedText.length > 0 {
            return true
        }
        return segments.contains { segment in
            guard case .text(let attributedText) = segment else { return false }
            return attributedText.length > 0
        }
    }
}

struct FirePostTextExpansionState: Hashable, Sendable {
    static let collapsedLineLimit = 4

    let isCollapsible: Bool
    let isExpanded: Bool

    static let disabled = FirePostTextExpansionState(
        isCollapsible: false,
        isExpanded: true
    )

    var isCollapsed: Bool {
        isCollapsible && !isExpanded
    }
}

struct FirePostCellRenderPayload {
    let post: TopicPostState
    let renderContent: FireTopicPostRenderContent
    let baseURLString: String
    let canWriteInteractions: Bool
    let isMutating: Bool
    let replyContext: String?
    let replyTargetPostNumber: UInt32?
    let replyShortcutCount: UInt32?
    let isLoadingReplyContext: Bool
    let textExpansionState: FirePostTextExpansionState
    let isSearchHighlighted: Bool
    let showsDivider: Bool
    let layoutWidth: CGFloat
    let boostAnimationsEnabled: Bool
    let layout: FirePostCellLayout?
    let layoutKey: FirePostCellLayoutKey?

    init(
        post: TopicPostState,
        renderContent: FireTopicPostRenderContent,
        baseURLString: String,
        canWriteInteractions: Bool,
        isMutating: Bool,
        replyContext: String?,
        replyTargetPostNumber: UInt32?,
        replyShortcutCount: UInt32? = nil,
        isLoadingReplyContext: Bool = false,
        textExpansionState: FirePostTextExpansionState,
        isSearchHighlighted: Bool = false,
        showsDivider: Bool,
        layoutWidth: CGFloat,
        boostAnimationsEnabled: Bool = true,
        layout: FirePostCellLayout? = nil,
        layoutKey: FirePostCellLayoutKey? = nil
    ) {
        self.post = post
        self.renderContent = renderContent
        self.baseURLString = baseURLString
        self.canWriteInteractions = canWriteInteractions
        self.isMutating = isMutating
        self.replyContext = replyContext
        self.replyTargetPostNumber = replyTargetPostNumber
        self.replyShortcutCount = replyShortcutCount
        self.isLoadingReplyContext = isLoadingReplyContext
        self.textExpansionState = textExpansionState
        self.isSearchHighlighted = isSearchHighlighted
        self.showsDivider = showsDivider
        self.layoutWidth = layoutWidth
        self.boostAnimationsEnabled = boostAnimationsEnabled
        self.layout = layout
        self.layoutKey = layoutKey
    }
}

struct FirePostCellCallbacks {
    let onLinkTapped: (URL) -> Void
    let onOpenProfile: (String) -> Void
    let onOpenImage: (FireCookedImage) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void
    let onOpenReactionPicker: (TopicPostState) -> Void
    let onQuotePost: (TopicPostState) -> Void
    let onEditPost: (TopicPostState) -> Void
    let onBookmarkPost: (TopicPostState) -> Void
    let onDeletePost: (TopicPostState) -> Void
    let onRecoverPost: (TopicPostState) -> Void
    let onFlagPost: (TopicPostState) -> Void
    let onOpenReplyTarget: (UInt32) -> Void
    let onOpenReplies: (TopicPostState) -> Void
    let onExpandText: (TopicPostState) -> Void
    let onVotePoll: (TopicPostState, PollState, [String]) -> Void
    let onUnvotePoll: (TopicPostState, PollState) -> Void
    let onSwipeReply: (TopicPostState) -> Void
}

enum FirePostAuthorMetadataDisplay {
    static func displayName(for post: TopicPostState) -> String {
        cleaned(post.name) ?? cleaned(post.username) ?? "Unknown"
    }

    static func primaryBadgeParts(for post: TopicPostState) -> [String] {
        let metadata = post.authorMetadata
        let title = cleaned(metadata.userTitle)
        let group = cleaned(metadata.primaryGroupName)
        let flair = cleaned(metadata.flairName)

        var parts: [String] = []
        if let title,
           let trustLevel = normalizedTrustLevelLabel(from: title) {
            parts.append(trustLevel)
        }
        if metadata.admin {
            parts.append("管理员")
        }
        if metadata.moderator {
            parts.append("版主")
        }
        if metadata.groupModerator {
            parts.append("组版主")
        }
        if let group {
            parts.append(condensed(group))
        }
        if let flair,
           flair.caseInsensitiveCompare(group ?? "") != .orderedSame {
            parts.append(condensed(flair))
        }
        return Array(parts.prefix(4))
    }

    static func secondaryLineParts(for post: TopicPostState) -> [String] {
        let metadata = post.authorMetadata
        let username = cleaned(post.username)
        let statusDescription = cleaned(metadata.userStatusDescription)
        let statusEmoji = cleaned(metadata.userStatusEmoji).map { ":\($0):" }

        var parts: [String] = []
        if let username {
            parts.append("@\(username)")
        }
        if let title = cleaned(metadata.userTitle),
           normalizedTrustLevelLabel(from: title) == nil {
            parts.append(condensed(title, maxCharacters: 16))
        }
        if let statusDescription {
            parts.append(condensed(statusDescription, maxCharacters: 16))
        } else if let statusEmoji {
            parts.append(statusEmoji)
        }
        return parts
    }

    static func metadataParts(for post: TopicPostState) -> [String] {
        var parts = secondaryLineParts(for: post)
        parts.append(contentsOf: primaryBadgeParts(for: post))
        return parts
    }

    static func hasVisibleMetadata(_ post: TopicPostState) -> Bool {
        !primaryBadgeParts(for: post).isEmpty || !secondaryLineParts(for: post).isEmpty
    }

    static func contentToken(for post: TopicPostState) -> String {
        let metadata = post.authorMetadata
        var parts: [String] = []
        parts.reserveCapacity(10)
        parts.append(displayName(for: post))
        parts.append(primaryBadgeParts(for: post).joined(separator: "|"))
        parts.append(secondaryLineParts(for: post).joined(separator: "|"))
        parts.append(metadata.userId.map(String.init) ?? "")
        parts.append(metadata.flairUrl ?? "")
        parts.append(metadata.flairBgColor ?? "")
        parts.append(metadata.flairColor ?? "")
        parts.append(metadata.flairGroupId.map(String.init) ?? "")
        parts.append(String(metadata.admin))
        parts.append(String(metadata.moderator))
        parts.append(String(metadata.groupModerator))
        return parts.joined(separator: "\u{1F}")
    }

    private static func normalizedTrustLevelLabel(from value: String) -> String? {
        let lowercased = value.lowercased()
        let hasTrustLevelHint = lowercased.contains("trust")
            || lowercased.contains("level")
            || lowercased.contains("tl")
            || value.contains("等级")
        guard hasTrustLevelHint,
              let digit = value.first(where: { $0.isNumber }) else {
            return nil
        }
        return "Lv.\(digit)"
    }

    private static func condensed(_ value: String, maxCharacters: Int = 10) -> String {
        guard value.count > maxCharacters, maxCharacters > 3 else {
            return value
        }
        return "\(value.prefix(maxCharacters - 3))..."
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
