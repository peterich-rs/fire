import AsyncDisplayKit
import Foundation
import UIKit

enum FirePostCellLayoutCalculator {
    static let maxVisualDepth = 3
    static let outerHorizontalPadding: CGFloat = 16
    static let indentWidthPerDepth: CGFloat = 20
    static let avatarSizeRoot: CGFloat = 32
    static let avatarSizeNested: CGFloat = 26
    static let avatarSpacingRoot: CGFloat = 10
    static let avatarSpacingNested: CGFloat = 6
    static let avatarThreadLineTopPadding: CGFloat = 6
    static let threadLineWidth: CGFloat = 1
    static let metaLineSpacing: CGFloat = 5
    static let textTopSpacing: CGFloat = 0
    static let imageTopSpacing: CGFloat = 10
    static let imageSpacing: CGFloat = 10
    static let replyShortcutTopSpacing: CGFloat = 8
    static let replyShortcutHeight: CGFloat = 30
    static let boostTopSpacing: CGFloat = 4
    static let boostSpacing: CGFloat = 6
    static let boostHorizontalInset: CGFloat = 10
    static let boostVerticalInset: CGFloat = 6
    static let fixedBoostManualRows = 2
    static let fixedBoostManualRowHeight: CGFloat = 26
    static let fixedBoostManualRowSpacing: CGFloat = 2
    static let fixedBoostManualHeight: CGFloat =
        CGFloat(fixedBoostManualRows) * fixedBoostManualRowHeight
        + CGFloat(fixedBoostManualRows - 1) * fixedBoostManualRowSpacing
    static let fixedBoostManualMinChipWidth: CGFloat = 48
    static let fixedBoostManualMaxChipWidthRatio: CGFloat = 0.72
    static let actionRowTopSpacing: CGFloat = 8
    static let actionRowHeight: CGFloat = 30
    static let reactionTopSpacing: CGFloat = 0
    static let contentVerticalPadding: CGFloat = 8
    static let menuButtonSize: CGFloat = 20
    static let dividerHeight: CGFloat = 0.5
    static let commentImageWidthScale: CGFloat = 0.78
    static let commentImageMaxWidth: CGFloat = 300
    static let commentImageMaxHeight: CGFloat = 260
    static let topicImageMaxHeight: CGFloat = 400

    static func visualDepth(for depth: Int) -> Int {
        max(depth - 1, 0)
    }

    static func indentWidth(for depth: Int) -> CGFloat {
        CGFloat(min(visualDepth(for: depth), maxVisualDepth)) * indentWidthPerDepth
    }

    static func avatarSize(for depth: Int) -> CGFloat {
        visualDepth(for: depth) > 0 ? avatarSizeNested : avatarSizeRoot
    }

    static func avatarSpacing(for depth: Int) -> CGFloat {
        visualDepth(for: depth) > 0 ? avatarSpacingNested : avatarSpacingRoot
    }

    static func usesFullWidthBody(for depth: Int) -> Bool {
        depth == 0
    }

    static func bodyLeadingOffset(for depth: Int) -> CGFloat {
        usesFullWidthBody(for: depth) ? 0 : avatarSize(for: depth) + avatarSpacing(for: depth)
    }

    static func availableContentWidth(
        for key: FirePostCellLayoutKey,
        trait: FirePostLayoutTraitSignature
    ) -> CGFloat {
        let contentWidth = CGFloat(trait.contentWidthPixels)
        let bodyLeading = outerHorizontalPadding
            + indentWidth(for: key.depth)
            + bodyLeadingOffset(for: key.depth)
        return max(contentWidth - bodyLeading - outerHorizontalPadding, 1)
    }

    static func calculate(
        key: FirePostCellLayoutKey,
        textHeight: CGFloat?,
        imageSizes: [CGSize],
        pollHeights: [CGFloat] = [],
        boostLines: [String] = [],
        trait: FirePostLayoutTraitSignature
    ) -> FirePostCellLayout {
        let indent = indentWidth(for: key.depth)
        let avatarSz = avatarSize(for: key.depth)
        let avatarSp = avatarSpacing(for: key.depth)
        let contentWidth = CGFloat(trait.contentWidthPixels)

        let headerLeading = outerHorizontalPadding + indent + avatarSz + avatarSp
        let bodyLeading = outerHorizontalPadding + indent + bodyLeadingOffset(for: key.depth)
        let contentTrailing = outerHorizontalPadding
        let headerAvailableWidth = max(contentWidth - headerLeading - contentTrailing, 1)
        let bodyAvailableWidth = max(contentWidth - bodyLeading - contentTrailing, 1)

        var cursorY = contentVerticalPadding

        // Avatar frame
        let avatarFrame = CGRect(
            x: outerHorizontalPadding + indent,
            y: 0,
            width: avatarSz,
            height: avatarSz
        )

        // Thread line frame
        let threadLineFrame: CGRect?
        if key.showsThreadLine {
            threadLineFrame = CGRect(
                x: outerHorizontalPadding + indent + avatarSz / 2 - threadLineWidth / 2,
                y: avatarFrame.maxY + avatarThreadLineTopPadding,
                width: threadLineWidth,
                height: 0
            )
        } else {
            threadLineFrame = nil
        }

        // Meta line
        let contentSizeCategory = UIContentSizeCategory(rawValue: trait.contentSizeCategory)
        let contentTraitCollection = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        let metaHeight = ceil(max(
            UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: contentTraitCollection).lineHeight,
            UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: contentTraitCollection).lineHeight,
            menuButtonSize
        ))
        let metaFrame = CGRect(
            x: headerLeading,
            y: cursorY,
            width: headerAvailableWidth,
            height: metaHeight
        )
        let metadataHeight = ceil(UIFont.preferredFont(
            forTextStyle: .caption2,
            compatibleWith: contentTraitCollection
        ).lineHeight)
        cursorY += metaHeight + metaLineSpacing + metadataHeight + metaLineSpacing

        // Text frame
        let textFrame: CGRect?
        let textContainerSize: CGSize
        let shouldCollapseText: Bool
        let textExpansionFrame: CGRect?
        if let textHeight, textHeight > 0 {
            let collapsedTextHeight = collapsedTextHeight(
                contentSizeCategory: UIContentSizeCategory(rawValue: trait.contentSizeCategory)
            )
            shouldCollapseText = key.textExpansionState.isCollapsed
                && textHeight > collapsedTextHeight
            let displayedTextHeight = shouldCollapseText
                ? collapsedTextHeight
                : textHeight
            textContainerSize = CGSize(width: bodyAvailableWidth, height: displayedTextHeight)
            textFrame = CGRect(
                x: bodyLeading,
                y: cursorY,
                width: bodyAvailableWidth,
                height: displayedTextHeight
            )
            cursorY += displayedTextHeight + textTopSpacing
            if shouldCollapseText {
                textExpansionFrame = textFrame
            } else {
                textExpansionFrame = nil
            }
        } else {
            textFrame = nil
            textContainerSize = .zero
            shouldCollapseText = false
            textExpansionFrame = nil
        }

        // Image frames
        var imageFrames: [CGRect] = []
        if !shouldCollapseText {
            for (index, imageSize) in imageSizes.enumerated() {
                if index == 0 {
                    if textFrame != nil {
                        cursorY += metaLineSpacing
                    }
                } else {
                    cursorY += imageSpacing
                }
                let frame = CGRect(
                    x: bodyLeading,
                    y: cursorY,
                    width: min(imageSize.width, bodyAvailableWidth),
                    height: imageSize.height
                )
                imageFrames.append(frame)
                cursorY += imageSize.height
            }
        }

        // Poll frames
        var pollFrames: [CGRect] = []
        if !shouldCollapseText {
            for (index, pollHeight) in pollHeights.enumerated() where pollHeight > 0 {
                if index == 0 {
                    if textFrame != nil || !imageFrames.isEmpty {
                        cursorY += imageSpacing
                    }
                } else {
                    cursorY += imageSpacing
                }
                let frame = CGRect(
                    x: bodyLeading,
                    y: cursorY,
                    width: bodyAvailableWidth,
                    height: pollHeight
                )
                pollFrames.append(frame)
                cursorY += pollHeight
            }
        }

        // Boost frames
        var boostFrames: [CGRect] = []
        if !shouldCollapseText && boostLines.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            if textFrame != nil || !imageFrames.isEmpty || !pollFrames.isEmpty {
                cursorY += boostTopSpacing
            }
            let boostHeight = fixedBoostManualHeight(
                boostLines: boostLines,
                containerWidth: bodyAvailableWidth,
                contentSizeCategory: contentSizeCategory
            )
            let frame = CGRect(
                x: bodyLeading,
                y: cursorY,
                width: bodyAvailableWidth,
                height: boostHeight
            )
            boostFrames.append(frame)
            cursorY += boostHeight
        }

        // Action row: reactions share one compact line below content.
        let replyShortcutFrame: CGRect?
        let reactionsFrame: CGRect?
        let hasActionRow = key.replyShortcutCount != nil || key.hasReactions
        if hasActionRow {
            if textFrame != nil || !imageFrames.isEmpty || !pollFrames.isEmpty || !boostFrames.isEmpty {
                if key.replyShortcutCount != nil {
                    cursorY += replyShortcutTopSpacing
                } else if boostFrames.isEmpty {
                    cursorY += actionRowTopSpacing
                }
            }

            let actionRowY = cursorY
            let actionSpacing: CGFloat = 8
            var actionX = bodyLeading
            let rowMaxX = bodyLeading + bodyAvailableWidth

            if key.replyShortcutCount != nil {
                let remaining = max(rowMaxX - actionX, 1)
                let reservedReactionWidth: CGFloat = key.hasReactions && remaining > 180 ? 96 : 0
                let width = max(remaining - reservedReactionWidth - actionSpacing, min(remaining, 96))
                replyShortcutFrame = CGRect(
                    x: actionX,
                    y: actionRowY,
                    width: min(width, remaining),
                    height: Self.replyShortcutHeight
                )
                actionX = min(actionX + min(width, remaining) + actionSpacing, rowMaxX)
            } else {
                replyShortcutFrame = nil
            }

            if key.hasReactions {
                reactionsFrame = CGRect(
                    x: actionX,
                    y: actionRowY,
                    width: max(rowMaxX - actionX, 1),
                    height: Self.actionRowHeight
                )
            } else {
                reactionsFrame = nil
            }

            cursorY += Self.actionRowHeight
        } else {
            replyShortcutFrame = nil
            reactionsFrame = nil
        }

        let contentBottom = cursorY + contentVerticalPadding
        var totalHeight = max(contentBottom, avatarFrame.maxY)

        // Divider frame
        let dividerFrame: CGRect?
        if key.showsDivider {
            dividerFrame = CGRect(
                x: outerHorizontalPadding,
                y: totalHeight,
                width: max(contentWidth - outerHorizontalPadding * 2, 1),
                height: dividerHeight
            )
            totalHeight += dividerHeight
        } else {
            dividerFrame = nil
        }

        // Update thread line height now that we know total height
        var resolvedThreadLineFrame = threadLineFrame
        if let tlFrame = threadLineFrame {
            resolvedThreadLineFrame = CGRect(
                x: tlFrame.minX,
                y: tlFrame.minY,
                width: tlFrame.width,
                height: totalHeight - tlFrame.minY
            )
        }

        return FirePostCellLayout(
            key: key,
            totalHeight: totalHeight,
            avatarFrame: avatarFrame,
            threadLineFrame: resolvedThreadLineFrame,
            metaFrame: metaFrame,
            textFrame: textFrame,
            textContainerSize: textContainerSize,
            textExpansionFrame: textExpansionFrame,
            imageFrames: imageFrames,
            pollFrames: pollFrames,
            boostFrames: boostFrames,
            replyShortcutFrame: replyShortcutFrame,
            reactionsFrame: reactionsFrame,
            menuFrame: nil,
            dividerFrame: dividerFrame
        )
    }

    static func measureRichTextHeight(
        attributedText: NSAttributedString?,
        containerWidth: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> CGFloat? {
        guard let attributedText, attributedText.length > 0 else {
            return nil
        }

        let textNode = ASTextNode()
        textNode.attributedText = attributedText
        textNode.maximumNumberOfLines = 0
        let width = max(containerWidth, 1)
        let layout = textNode.layoutThatFits(ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: .greatestFiniteMagnitude)
        ))
        return ceil(layout.size.height)
    }

    static func estimatedRichTextHeight(
        plainText: String,
        hasAttributedText: Bool,
        containerWidth: CGFloat,
        contentSizeCategory: UIContentSizeCategory,
        textExpansionState: FirePostTextExpansionState
    ) -> CGFloat? {
        guard hasAttributedText || !plainText.isEmpty else {
            return nil
        }

        let font = UIFont.preferredFont(
            forTextStyle: .subheadline,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        )
        let lineHeight = max(font.lineHeight, 1)
        let averageGlyphWidth = max(font.pointSize * 0.56, 1)
        let charactersPerLine = max(Int((max(containerWidth, 1) / averageGlyphWidth).rounded(.down)), 1)
        let logicalLineCount = plainText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { partialResult, line in
                partialResult + max(Int(ceil(Double(line.count) / Double(charactersPerLine))), 1)
            }
        let resolvedLineCount = max(logicalLineCount, 1)
        if textExpansionState.isCollapsed,
           resolvedLineCount > FirePostTextExpansionState.collapsedLineLimit {
            return collapsedTextHeight(contentSizeCategory: contentSizeCategory) + 1
        }
        let displayedLineCount = textExpansionState.isCollapsed
            ? min(resolvedLineCount, FirePostTextExpansionState.collapsedLineLimit)
            : resolvedLineCount
        return ceil(CGFloat(displayedLineCount) * lineHeight)
    }

    static func boostHeight(
        text: String,
        containerWidth: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let traitCollection = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        let font = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
        let maxTextWidth = max(containerWidth - boostHorizontalInset * 2, 1)
        let boundingRect = (trimmed as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: font.lineHeight * 2.4),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let lineHeight = ceil(font.lineHeight)
        let textHeight = min(ceil(boundingRect.height), lineHeight * 2)
        return max(textHeight + boostVerticalInset * 2, lineHeight + boostVerticalInset * 2)
    }

    static func fixedBoostManualHeight(forUsedRowCount usedRowCount: Int) -> CGFloat {
        let rowCount = min(max(usedRowCount, 1), fixedBoostManualRows)
        return CGFloat(rowCount) * fixedBoostManualRowHeight
            + CGFloat(rowCount - 1) * fixedBoostManualRowSpacing
    }

    static func fixedBoostManualHeight(
        boostLines: [String],
        containerWidth: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        let chipWidths = fixedBoostManualChipWidths(
            boostLines: boostLines,
            containerWidth: containerWidth,
            contentSizeCategory: contentSizeCategory
        )
        guard !chipWidths.isEmpty else { return 0 }
        let layout = FirePostBoostManualLayout.placements(
            forChipWidths: chipWidths,
            pageWidth: containerWidth,
            laneCount: fixedBoostManualRows
        )
        return fixedBoostManualHeight(forUsedRowCount: layout.usedRowCount)
    }

    private static func fixedBoostManualChipWidths(
        boostLines: [String],
        containerWidth: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> [CGFloat] {
        let traitCollection = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        let font = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
        let maxChipWidth = max(containerWidth * fixedBoostManualMaxChipWidthRatio, 1)
        return boostLines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let attributedText = NSAttributedString(
                string: trimmed,
                attributes: [.font: font]
            )
            return FirePostBoostManualLayout.chipWidth(
                for: attributedText,
                maxWidth: maxChipWidth,
                horizontalInset: boostHorizontalInset,
                minWidth: fixedBoostManualMinChipWidth
            )
        }
    }

    static func collapsedTextHeight(contentSizeCategory: UIContentSizeCategory) -> CGFloat {
        let font = UIFont.preferredFont(
            forTextStyle: .subheadline,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        )
        return ceil(font.lineHeight * CGFloat(FirePostTextExpansionState.collapsedLineLimit))
    }

    static func imageRenderSize(
        for image: FireCookedImage,
        availableWidth: CGFloat,
        depth: Int
    ) -> CGSize {
        let aspectRatio = max(image.aspectRatio ?? 1.45, 0.01)
        if usesFullWidthBody(for: depth) {
            let width = max(availableWidth, 1)
            return CGSize(width: width, height: width / aspectRatio)
        }

        let isCommentImage = depth > 0
        let maxWidth = isCommentImage
            ? min(max(availableWidth * commentImageWidthScale, 1), commentImageMaxWidth)
            : availableWidth
        let rawHeight = maxWidth / aspectRatio
        let maxHeight = isCommentImage ? commentImageMaxHeight : topicImageMaxHeight
        if rawHeight > maxHeight {
            return CGSize(width: maxHeight * aspectRatio, height: maxHeight)
        }
        return CGSize(width: maxWidth, height: rawHeight)
    }

}
