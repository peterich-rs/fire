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
    let isReplyThreadExpanded: Bool
    /// Compact bottom controls (reply/react/boost + overflow) instead of a header menu.
    let showsInlineActions: Bool
    /// Always-visible primary icons: reply / react / boost / overflow.
    let primaryActionSlotCount: Int
    /// Inline quick-reaction strip expanded under the action row.
    let isReactionPickerExpanded: Bool
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
        isReplyThreadExpanded: Bool = false,
        showsInlineActions: Bool = false,
        primaryActionSlotCount: Int = 0,
        isReactionPickerExpanded: Bool = false,
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
        self.isReplyThreadExpanded = isReplyThreadExpanded
        self.showsInlineActions = showsInlineActions
        self.primaryActionSlotCount = max(primaryActionSlotCount, 0)
        self.isReactionPickerExpanded = isReactionPickerExpanded
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
    /// Keep chips compact on one dedicated row; overflow is summarized.
    static let visibleReactionLimit = 6
    static let wrappedReactionMaxLines = 1

    static func visibleReactions(
        from reactions: [TopicReactionState],
        depth: Int
    ) -> [TopicReactionState] {
        _ = depth
        // Highest-count first so the densest reactions stay visible.
        let sorted = reactions.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
        return Array(sorted.prefix(visibleReactionLimit))
    }

    static func hiddenReactionCount(
        from reactions: [TopicReactionState],
        depth: Int
    ) -> Int {
        max(0, reactions.count - visibleReactions(from: reactions, depth: depth).count)
    }

    /// Reactions always live on their own full-width row under the action icons.
    static func allowsWrapping(depth: Int) -> Bool {
        _ = depth
        return false
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

    /// Compact single-line chip content: body only.
    /// Author identity is carried by the leading avatar (Fluxdo-style), not `@username` text.
    static func compactChipContent(
        for boost: TopicPostBoostState,
        textColor: UIColor,
        usernameColor: UIColor = .systemBlue
    ) -> NSAttributedString {
        _ = usernameColor
        let bodyFont = UIFont.preferredFont(forTextStyle: .caption2)
        let body = strippedDisplayText(for: boost)
            ?? cleaned(boost.displayText)
            ?? ""
        guard !body.isEmpty else {
            return NSAttributedString()
        }
        return NSAttributedString(
            string: body,
            attributes: [
                .font: bodyFont,
                .foregroundColor: textColor,
            ]
        )
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

/// Collapsed ASTextNode treats blank lines (`\n\n`) as full visual lines, which
/// burns the 4-line budget and looks like huge row gaps. Normalize blank runs
/// to a single newline + paragraph spacing for collapsed display/measurement only.
///
/// Reply-quotes also get collapsed to a single header line (`引用 @user · #n`).
/// Without this, the post-level 4-line clamp cuts through the quote body, hides
/// the author's reply, and drops quote chrome (collapsed path uses ASTextNode).
enum FirePostCollapsedTextNormalizer {
    /// Inline expand control when quote bodies were elided but the remaining
    /// text still fits inside the 4-line clamp (so ASTextNode would not show
    /// its truncation token).
    static let expandTextURL = URL(string: "fire://post-text-expand")!

    static func attributedTextForCollapsedDisplay(
        _ attributedText: NSAttributedString,
        accentColor: UIColor = FireTheme.uiAccent
    ) -> NSAttributedString {
        guard attributedText.length > 0 else { return attributedText }

        let mutable = NSMutableAttributedString(attributedString: attributedText)
        let elidedQuoteBody = collapseQuoteBlocksToHeaderLines(in: mutable)
        collapseExcessiveBlankLines(in: mutable)
        if elidedQuoteBody {
            appendInlineExpandControl(to: mutable, accentColor: accentColor)
        }
        return mutable
    }

    static func isExpandTextURL(_ url: URL) -> Bool {
        url == expandTextURL
    }

    static func expansionTruncationToken(
        accentColor: UIColor = FireTheme.uiAccent
    ) -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let result = NSMutableAttributedString(
            string: "... ",
            attributes: [.font: font, .foregroundColor: UIColor.label]
        )
        result.append(NSAttributedString(
            string: "展开",
            attributes: [
                .font: font,
                .foregroundColor: accentColor,
                // Also a link so taps work when this token is inlined (not only
                // when ASTextNode attaches it as truncationAttributedText).
                .link: expandTextURL,
            ]
        ))
        return result
    }

    /// Returns `true` when at least one quote body was reduced to its header.
    @discardableResult
    private static func collapseQuoteBlocksToHeaderLines(
        in body: NSMutableAttributedString
    ) -> Bool {
        var quoteRanges: [NSRange] = []
        let fullRange = NSRange(location: 0, length: body.length)
        body.enumerateAttribute(
            .fireQuotePreviewBlock,
            in: fullRange,
            options: []
        ) { value, range, _ in
            guard value != nil, range.length > 0 else { return }
            quoteRanges.append(range)
        }
        guard !quoteRanges.isEmpty else { return false }

        var elidedAny = false
        // Replace from the end so earlier ranges stay valid.
        for range in quoteRanges.reversed() {
            let quote = body.attributedSubstring(from: range)
            let header = quoteHeaderLine(from: quote)
            let originalVisible = visibleContentCharacterCount(in: quote.string)
            let headerVisible = visibleContentCharacterCount(in: header.string)
            if headerVisible < originalVisible {
                elidedAny = true
            }
            body.replaceCharacters(in: range, with: header)
        }
        return elidedAny
    }

    private static func quoteHeaderLine(from quote: NSAttributedString) -> NSAttributedString {
        let source = quote.string as NSString
        let lineRanges = nonBlankContentLineRanges(in: source)
        guard let firstRange = lineRanges.first else {
            return NSAttributedString(string: "")
        }

        // Prefer the Discourse reply-quote chrome line (`引用 @user · #n`).
        let preferredRange = lineRanges.first { range in
            let line = source.substring(with: range)
            return line.hasPrefix("引用")
        } ?? firstRange

        let line = NSMutableAttributedString(attributedString: quote.attributedSubstring(from: preferredRange))
        // Drop quote-panel markers: collapsed path has no CALayer chrome, and a
        // partial panel range would look worse than a plain header.
        let full = NSRange(location: 0, length: line.length)
        if full.length > 0 {
            line.removeAttribute(.fireQuotePreviewBlock, range: full)
            line.removeAttribute(.fireQuotePreviewBackgroundColor, range: full)
            line.removeAttribute(.fireQuotePreviewStripeColor, range: full)
            line.addAttributes(
                [
                    .font: UIFont.preferredFont(forTextStyle: .caption1),
                    .foregroundColor: UIColor.secondaryLabel,
                ],
                range: full
            )
            // Keep link colors on @user / #floor so they stay tappable.
            line.enumerateAttribute(.link, in: full, options: []) { value, range, _ in
                guard value != nil else { return }
                line.addAttribute(
                    .foregroundColor,
                    value: FireTheme.uiAccent,
                    range: range
                )
            }
        }

        // Trailing newline separates the header from the author's reply text.
        if line.length > 0 {
            let trailing = NSMutableParagraphStyle()
            trailing.paragraphSpacing = 4
            trailing.lineBreakMode = .byTruncatingTail
            line.append(NSAttributedString(
                string: "\n",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .caption1),
                    .foregroundColor: UIColor.clear,
                    .paragraphStyle: trailing,
                ]
            ))
        }
        return line
    }

    private static func appendInlineExpandControl(
        to body: NSMutableAttributedString,
        accentColor: UIColor
    ) {
        // Avoid double "... 展开" if the last visible line already ends with it.
        let existing = body.string as NSString
        if existing.range(of: "展开", options: [.backwards]).location != NSNotFound,
           existing.length >= 2 {
            let tail = existing.substring(from: max(existing.length - 8, 0))
            if tail.contains("展开") {
                return
            }
        }
        if body.length > 0 {
            let last = (body.string as NSString).character(at: body.length - 1)
            if last != 10, last != 32 {
                body.append(NSAttributedString(
                    string: " ",
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .subheadline),
                        .foregroundColor: UIColor.label,
                    ]
                ))
            }
        }
        body.append(expansionTruncationToken(accentColor: accentColor))
    }

    private static func collapseExcessiveBlankLines(in body: NSMutableAttributedString) {
        // Walk backwards on the live string so ranges stay valid while editing.
        var index = body.length - 1
        while index >= 0 {
            let live = body.string as NSString
            guard live.character(at: index) == 10 else {
                index -= 1
                continue
            }
            var runStart = index
            while runStart > 0, live.character(at: runStart - 1) == 10 {
                runStart -= 1
            }
            let runLength = index - runStart + 1
            if runLength > 1 {
                // Keep one newline; blank-line visual spacing becomes paragraphSpacing.
                body.replaceCharacters(
                    in: NSRange(location: runStart, length: runLength),
                    with: "\n"
                )
                let styleLocation = max(runStart - 1, 0)
                if styleLocation < body.length {
                    let existing = body.attribute(
                        .paragraphStyle,
                        at: styleLocation,
                        effectiveRange: nil
                    ) as? NSParagraphStyle
                    let paragraph = (existing?.mutableCopy() as? NSMutableParagraphStyle)
                        ?? NSMutableParagraphStyle()
                    paragraph.paragraphSpacing = max(paragraph.paragraphSpacing, 6)
                    paragraph.lineBreakMode = .byWordWrapping
                    body.addAttribute(
                        .paragraphStyle,
                        value: paragraph,
                        range: NSRange(location: styleLocation, length: 1)
                    )
                }
            }
            index = runStart - 1
        }
    }

    private static func nonBlankContentLineRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var lineStart = 0
        while lineStart <= source.length {
            let searchRange = NSRange(location: lineStart, length: source.length - lineStart)
            let newlineRange = source.range(of: "\n", options: [], range: searchRange)
            let lineEnd = newlineRange.location == NSNotFound ? source.length : newlineRange.location
            let raw = NSRange(location: lineStart, length: lineEnd - lineStart)
            if let trimmed = trimmedContentRange(in: source, range: raw) {
                ranges.append(trimmed)
            }
            if lineEnd >= source.length {
                break
            }
            lineStart = lineEnd + 1
        }
        return ranges
    }

    private static func trimmedContentRange(in source: NSString, range: NSRange) -> NSRange? {
        var location = range.location
        var end = range.location + range.length
        let whitespace = CharacterSet.whitespacesAndNewlines
        while location < end {
            let scalarValue = source.character(at: location)
            if scalarValue == 0x200B {
                location += 1
                continue
            }
            guard let scalar = UnicodeScalar(scalarValue), whitespace.contains(scalar) else {
                break
            }
            location += 1
        }
        while end > location {
            let scalarValue = source.character(at: end - 1)
            if scalarValue == 0x200B {
                end -= 1
                continue
            }
            guard let scalar = UnicodeScalar(scalarValue), whitespace.contains(scalar) else {
                break
            }
            end -= 1
        }
        return location < end
            ? NSRange(location: location, length: end - location)
            : nil
    }

    private static func visibleContentCharacterCount(in string: String) -> Int {
        string.unicodeScalars.reduce(into: 0) { count, scalar in
            if scalar == "\u{200B}" { return }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return }
            count += 1
        }
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
    let isReplyThreadExpanded: Bool
    let isLoadingReplyContext: Bool
    let textExpansionState: FirePostTextExpansionState
    let isSearchHighlighted: Bool
    let showsDivider: Bool
    let layoutWidth: CGFloat
    let boostAnimationsEnabled: Bool
    let isReactionPickerExpanded: Bool
    let quickReactionOptions: [FireReactionOption]
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
        isReplyThreadExpanded: Bool = false,
        isLoadingReplyContext: Bool = false,
        textExpansionState: FirePostTextExpansionState,
        isSearchHighlighted: Bool = false,
        showsDivider: Bool,
        layoutWidth: CGFloat,
        boostAnimationsEnabled: Bool = true,
        isReactionPickerExpanded: Bool = false,
        quickReactionOptions: [FireReactionOption] = [],
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
        self.isReplyThreadExpanded = isReplyThreadExpanded
        self.isLoadingReplyContext = isLoadingReplyContext
        self.textExpansionState = textExpansionState
        self.isSearchHighlighted = isSearchHighlighted
        self.showsDivider = showsDivider
        self.layoutWidth = layoutWidth
        self.boostAnimationsEnabled = boostAnimationsEnabled
        self.isReactionPickerExpanded = isReactionPickerExpanded
        self.quickReactionOptions = quickReactionOptions
        self.layout = layout
        self.layoutKey = layoutKey
    }

    var showsInlineActions: Bool {
        // Prefer the layout-key decision (OP hides overflow; replies keep it).
        if let layoutKey {
            return layoutKey.showsInlineActions
        }
        return canWriteInteractions && !post.hidden
            || post.canEdit
            || post.canRecover
            || (post.canDelete && !post.hidden)
    }
}

struct FirePostCellCallbacks {
    let onLinkTapped: (URL) -> Void
    let onOpenProfile: (String) -> Void
    let onOpenImage: (FireCookedImage) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void
    let onToggleReactionPicker: (TopicPostState) -> Void
    let onReplyPost: (TopicPostState) -> Void
    let onBoostPost: (TopicPostState) -> Void
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

    /// Primary-line chips beside the display name.
    /// Align with Fluxdo: staff roles only. Trust title / flair / group are not text chips
    /// (flair belongs on the avatar; trust title sits on the secondary `@username` line).
    static func primaryBadgeParts(for post: TopicPostState) -> [String] {
        let metadata = post.authorMetadata
        var parts: [String] = []
        if metadata.admin {
            parts.append("管理员")
        }
        if metadata.moderator {
            parts.append("版主")
        }
        if metadata.groupModerator {
            parts.append("组版主")
        }
        return Array(parts.prefix(3))
    }

    /// Secondary line under the display name: `@username` + humanized title + status.
    static func secondaryLineParts(for post: TopicPostState) -> [String] {
        let metadata = post.authorMetadata
        let username = cleaned(post.username)
        let statusDescription = cleaned(metadata.userStatusDescription)
        let statusEmoji = cleaned(metadata.userStatusEmoji).map { ":\($0):" }

        var parts: [String] = []
        if let username {
            parts.append("@\(username)")
        }
        if let title = cleaned(metadata.userTitle) {
            parts.append(condensed(humanizedUserTitle(title), maxCharacters: 16))
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

    /// Map Discourse title keys such as `trust_lv_3` / `Trust Level 2` to readable labels.
    static func humanizedUserTitle(_ value: String) -> String {
        if let level = parsedTrustLevel(from: value) {
            return trustLevelDisplayLabel(level)
        }
        return value
    }

    static func parsedTrustLevel(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            #"(?i)trust[_\s-]*l(?:evel|v)[_\s-]*(\d+)"#,
            #"(?i)\btl[_\s-]*(\d+)\b"#,
            #"(?i)\blv\.?\s*(\d+)\b"#,
            #"(?i)\bl(\d+)\b"#,
            #"等级\s*(\d+)"#,
            #"(?i)level\s*(\d+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  match.numberOfRanges > 1,
                  let levelRange = Range(match.range(at: 1), in: trimmed),
                  let level = Int(trimmed[levelRange]) else {
                continue
            }
            return level
        }
        return nil
    }

    static func trustLevelDisplayLabel(_ level: Int) -> String {
        switch level {
        case 0: return "L0 新用户"
        case 1: return "L1 基本用户"
        case 2: return "L2 成员"
        case 3: return "L3 活跃用户"
        case 4: return "L4 领袖"
        default: return "L\(level)"
        }
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
