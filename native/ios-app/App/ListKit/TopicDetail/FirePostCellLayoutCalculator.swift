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
    static let metaLineSpacing: CGFloat = 8
    static let textTopSpacing: CGFloat = 0
    static let imageTopSpacing: CGFloat = 10
    static let imageSpacing: CGFloat = 10
    static let reactionTopSpacing: CGFloat = 0
    static let contentVerticalPadding: CGFloat = 8
    static let menuButtonSize: CGFloat = 20
    static let dividerHeight: CGFloat = 0.5

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

    static func availableContentWidth(
        for key: FirePostCellLayoutKey,
        trait: FirePostLayoutTraitSignature
    ) -> CGFloat {
        let contentWidth = CGFloat(trait.contentWidthPixels)
        let contentLeading = outerHorizontalPadding
            + indentWidth(for: key.depth)
            + avatarSize(for: key.depth)
            + avatarSpacing(for: key.depth)
        let contentTrailing = outerHorizontalPadding
        return max(contentWidth - contentLeading - contentTrailing, 1)
    }

    static func calculate(
        key: FirePostCellLayoutKey,
        textHeight: CGFloat?,
        imageHeights: [CGFloat],
        trait: FirePostLayoutTraitSignature
    ) -> FirePostCellLayout {
        let indent = indentWidth(for: key.depth)
        let avatarSz = avatarSize(for: key.depth)
        let avatarSp = avatarSpacing(for: key.depth)
        let contentWidth = CGFloat(trait.contentWidthPixels)

        let contentLeading = outerHorizontalPadding + indent + avatarSz + avatarSp
        let contentTrailing = outerHorizontalPadding
        let contentAvailableWidth = max(contentWidth - contentLeading - contentTrailing, 1)

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
        let metaHeight: CGFloat = 20
        let metaFrame = CGRect(
            x: contentLeading,
            y: cursorY,
            width: contentAvailableWidth,
            height: metaHeight
        )
        cursorY += metaHeight + metaLineSpacing

        // Text frame
        let textFrame: CGRect?
        let textContainerSize: CGSize
        if let textHeight, textHeight > 0 {
            textContainerSize = CGSize(width: contentAvailableWidth, height: textHeight)
            textFrame = CGRect(
                x: contentLeading,
                y: cursorY,
                width: contentAvailableWidth,
                height: textHeight
            )
            cursorY += textHeight + textTopSpacing
        } else {
            textFrame = nil
            textContainerSize = .zero
        }

        // Image frames
        var imageFrames: [CGRect] = []
        for (index, imageHeight) in imageHeights.enumerated() {
            if index == 0 {
                if textFrame != nil {
                    cursorY += metaLineSpacing
                }
            } else {
                cursorY += imageSpacing
            }
            let frame = CGRect(
                x: contentLeading,
                y: cursorY,
                width: contentAvailableWidth,
                height: imageHeight
            )
            imageFrames.append(frame)
            cursorY += imageHeight
        }

        // Reactions frame
        let reactionsFrame: CGRect?
        if key.hasReactions {
            if textFrame != nil || !imageFrames.isEmpty {
                cursorY += metaLineSpacing
            }
            let reactionHeight: CGFloat = 32
            reactionsFrame = CGRect(
                x: contentLeading,
                y: cursorY,
                width: contentAvailableWidth,
                height: reactionHeight
            )
            cursorY += reactionHeight
        } else {
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
            imageFrames: imageFrames,
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

        let width = max(containerWidth, 1)
        let textStorage = NSTextStorage(attributedString: attributedText)
        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        if attributedText.attribute(.font, at: 0, effectiveRange: nil) == nil {
            let scaledFont = UIFont.preferredFont(
                forTextStyle: .subheadline,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
            )
            textStorage.addAttribute(
                .font,
                value: scaledFont,
                range: NSRange(location: 0, length: textStorage.length)
            )
        }

        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        return ceil(rect.height)
    }

    static func imageHeight(for image: FireCookedImage, availableWidth: CGFloat) -> CGFloat {
        let aspectRatio = image.aspectRatio ?? 1.45
        return availableWidth / aspectRatio
    }
}
