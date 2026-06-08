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
        Array(boosts.compactMap { cleaned($0.displayText) }.prefix(bodyBarrageVisibleLineLimit))
    }

    static func bodyBarrageBatchSignature(
        postID: UInt64,
        boosts: [TopicPostBoostState]
    ) -> String {
        let boostTokens = boosts.compactMap { boost -> String? in
            guard let text = cleaned(boost.displayText) else { return nil }
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
        cleaned(boost.displayText) ?? ""
    }

    static func contentToken(for boosts: [TopicPostBoostState]) -> String {
        boosts.map { boost in
            [
                String(boost.id),
                boost.user.username,
                boost.user.name ?? "",
                boost.displayText,
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
    let replyContextError: String?
    let textExpansionState: FirePostTextExpansionState
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
        replyShortcutCount: UInt32?,
        isLoadingReplyContext: Bool,
        replyContextError: String? = nil,
        textExpansionState: FirePostTextExpansionState,
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
        self.replyContextError = replyContextError
        self.textExpansionState = textExpansionState
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
