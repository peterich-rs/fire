import AsyncDisplayKit
import UIKit

final class FireTopicDetailHeaderCellNode: ASCellNode {
    private let titleNode = ASTextNode()
    private let chipNodes: [ASButtonNode]

    init(
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot = FireAppearanceEnvironment.snapshot(traits: .current)
    ) {
        var chips: [ASButtonNode] = []
        let titleInk = appearance.ink

        titleNode.attributedText = NSAttributedString(
            string: configuration.displayedTopicTitle,
            attributes: [
                .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .title3, weight: .bold),
                .foregroundColor: titleInk,
            ]
        )
        titleNode.maximumNumberOfLines = 0
        titleNode.style.flexShrink = 1.0
        // Avoid Texture opaque default fill painting a black title strip on light canvas.
        titleNode.isOpaque = false
        titleNode.backgroundColor = .clear
        titleNode.displaysAsynchronously = false

        if configuration.isPrivateMessageThread {
            chips.append(Self.makeChip(
                title: "私信",
                foregroundColor: FireTopicDetailCellColors.accent,
                backgroundColor: FireTopicDetailCellColors.accent.withAlphaComponent(0.12)
            ))

            for participant in configuration.displayedParticipants {
                let label = (participant.name ?? "").ifEmpty(participant.username ?? "用户 \(participant.userId)")
                chips.append(Self.makeChip(
                    title: "@\(label)",
                    foregroundColor: FireTopicDetailCellColors.privateMessageForeground,
                    backgroundColor: FireTopicDetailCellColors.privateMessageForeground.withAlphaComponent(0.12)
                ))
            }
        } else {
            if let category = configuration.displayedCategory {
                let accent = UIColor(fireHex: category.colorHex) ?? FireTopicDetailCellColors.accent
                chips.append(Self.makeChip(
                    title: category.displayName,
                    foregroundColor: accent,
                    backgroundColor: FireTopicDetailCellColors.categoryChipBackground(accent: accent),
                    action: configuration.viewModel == nil ? nil : {
                        configuration.onOpenCategory(category)
                    }
                ))
            }

            for tagName in configuration.displayedTagNames {
                chips.append(Self.makeChip(
                    title: "#\(tagName)",
                    foregroundColor: FireTopicDetailCellColors.tagChipForeground,
                    backgroundColor: FireTopicDetailCellColors.tagChipBackground,
                    horizontalInset: 6,
                    verticalInset: 3,
                    action: configuration.viewModel == nil ? nil : {
                        configuration.onOpenTag(tagName)
                    }
                ))
            }

            for label in configuration.row.statusLabels {
                chips.append(Self.makeChip(
                    title: label,
                    foregroundColor: FireTopicDetailCellColors.accent,
                    backgroundColor: FireTopicDetailCellColors.accent.withAlphaComponent(0.12)
                ))
            }
        }

        chipNodes = chips
        super.init()
        automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: self)
        isAccessibilityElement = true
        accessibilityLabel = [configuration.displayedTopicTitle, chips.compactMap(\.accessibilityLabel).joined(separator: ", ")]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        var children: [ASLayoutElement] = [titleNode]
        if !chipNodes.isEmpty {
            let chipStack = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 6,
                justifyContent: .start,
                alignItems: .start,
                children: chipNodes
            )
            chipStack.flexWrap = .wrap
            chipStack.alignContent = .start
            chipStack.lineSpacing = 6
            children.append(chipStack)
        }

        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8,
            justifyContent: .start,
            alignItems: .stretch,
            children: children
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 16, left: 16, bottom: 0, right: 16),
            child: stack
        )
    }

    private static func makeChip(
        title: String,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        horizontalInset: CGFloat = 8,
        verticalInset: CGFloat = 4,
        action: (() -> Void)? = nil
    ) -> ASButtonNode {
        let node = FireTopicDetailChipButtonNode(action: action)
        node.setAttributedTitle(
            NSAttributedString(
                string: title,
                attributes: [
                    .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .caption2, weight: .medium),
                    .foregroundColor: foregroundColor,
                ]
            ),
            for: .normal
        )
        node.contentEdgeInsets = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
        node.backgroundColor = backgroundColor
        node.cornerRadius = 12
        node.clipsToBounds = true
        node.isEnabled = action != nil
        node.accessibilityLabel = title
        if action != nil {
            node.accessibilityTraits.insert(.button)
        }
        return node
    }
}

