import AsyncDisplayKit
import UIKit

final class FireTopicDetailAISummaryCellNode: ASCellNode, FireTopicDetailChromeCellNode {
    private let backgroundNode = ASDisplayNode()
    private let headerButtonNode: FireTopicDetailChipButtonNode
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let statusNode = ASTextNode()
    private let chevronNode = ASImageNode()
    private let bodyNode = ASTextNode()
    private let metadataNode = ASTextNode()
    private var isExpanded: Bool

    init(
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot = FireAppearanceEnvironment.snapshot(traits: .current)
    ) {
        let summary = configuration.topicAiSummary
        isExpanded = configuration.isTopicAiSummaryExpanded && summary != nil
        let primaryInk = appearance.ink
        let secondaryInk = appearance.subtleInk
        let tertiaryInk = appearance.tertiaryInk

        backgroundNode.backgroundColor = .secondarySystemBackground
        backgroundNode.cornerRadius = 8
        backgroundNode.clipsToBounds = true

        iconNode.image = UIImage(systemName: "sparkles")?.withTintColor(
            FireTopicDetailCellColors.accent,
            renderingMode: .alwaysOriginal
        )
        iconNode.style.preferredSize = CGSize(width: 17, height: 17)

        titleNode.attributedText = NSAttributedString(
            string: "AI 摘要",
            attributes: [
                .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .subheadline, weight: .semibold),
                .foregroundColor: primaryInk,
            ]
        )

        if summary?.outdated == true {
            statusNode.attributedText = NSAttributedString(
                string: "有新回复",
                attributes: [
                    .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .caption2, weight: .semibold),
                    .foregroundColor: FireTopicDetailCellColors.warning,
                ]
            )
            statusNode.backgroundColor = FireTopicDetailCellColors.warning.withAlphaComponent(0.12)
            statusNode.cornerRadius = 10
            statusNode.textContainerInset = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        } else {
            statusNode.isHidden = true
        }

        let chevronName = isExpanded ? "chevron.up" : "chevron.down"
        chevronNode.image = UIImage(systemName: chevronName)?.withTintColor(
            tertiaryInk,
            renderingMode: .alwaysOriginal
        )
        chevronNode.style.preferredSize = CGSize(width: 14, height: 14)

        if let summary, isExpanded {
            bodyNode.attributedText = NSAttributedString(
                string: summary.summarizedText,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: primaryInk,
                ]
            )
            bodyNode.maximumNumberOfLines = 0
            bodyNode.style.flexShrink = 1.0

            let metadata = Self.metadata(for: summary)
            if !metadata.isEmpty {
                metadataNode.attributedText = NSAttributedString(
                    string: metadata.joined(separator: " · "),
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .caption2),
                        .foregroundColor: secondaryInk,
                    ]
                )
                metadataNode.maximumNumberOfLines = 0
            } else {
                metadataNode.isHidden = true
            }
        } else {
            bodyNode.isHidden = true
            metadataNode.isHidden = true
        }

        headerButtonNode = FireTopicDetailChipButtonNode(action: configuration.onToggleTopicAiSummaryExpanded)
        headerButtonNode.accessibilityLabel = isExpanded ? "收起 AI 摘要" : "展开 AI 摘要"

        super.init()
        automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: self)
        FireAppearanceTexture.configureChromeTextNode(titleNode)
        FireAppearanceTexture.configureChromeTextNode(statusNode)
        FireAppearanceTexture.configureChromeTextNode(bodyNode)
        FireAppearanceTexture.configureChromeTextNode(metadataNode)
        isAccessibilityElement = false
        accessibilityElements = [headerButtonNode, bodyNode, metadataNode].filter { !$0.isHidden }
        headerButtonNode.accessibilityValue = [
            statusNode.isHidden ? nil : "有新回复",
            isExpanded ? bodyNode.attributedText?.string : "已折叠",
            isExpanded ? metadataNode.attributedText?.string : nil,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "，")
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let headerSpacer = ASLayoutSpec()
        headerSpacer.style.flexGrow = 1.0
        let headerChildren: [ASLayoutElement] = [
            iconNode,
            titleNode,
            headerSpacer,
            statusNode,
            chevronNode,
        ].filter { element in
            guard let node = element as? ASDisplayNode else { return true }
            return !node.isHidden
        }
        let headerContent = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8,
            justifyContent: .start,
            alignItems: .center,
            children: headerChildren
        )
        let headerButtonSpec = ASBackgroundLayoutSpec(
            child: headerContent,
            background: headerButtonNode
        )
        headerButtonNode.style.flexGrow = 1.0
        headerButtonNode.style.alignSelf = .stretch

        var contentChildren: [ASLayoutElement] = [headerButtonSpec]
        if !bodyNode.isHidden {
            contentChildren.append(bodyNode)
        }
        if !metadataNode.isHidden {
            contentChildren.append(metadataNode)
        }

        let contentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: isExpanded ? 10 : 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: contentChildren
        )
        let paddedContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14),
            child: contentStack
        )
        let card = ASBackgroundLayoutSpec(child: paddedContent, background: backgroundNode)
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 4, left: 16, bottom: 10, right: 16),
            child: card
        )
    }

    private static func metadata(for summary: TopicAiSummaryState) -> [String] {
        var metadata: [String] = []
        if let updatedAt = FireTopicPresentation.formatTimestamp(summary.updatedAt) {
            metadata.append("更新 \(updatedAt)")
        }
        if summary.outdated, summary.newPostsSinceSummary > 0 {
            metadata.append("\(summary.newPostsSinceSummary) 条新回复")
        }
        if let algorithm = summary.algorithm?.trimmingCharacters(in: .whitespacesAndNewlines),
           !algorithm.isEmpty {
            metadata.append(algorithm)
        }
        if summary.canRegenerate {
            metadata.append("可重新生成")
        }
        return metadata
    }

    func apply(
        item _: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) {
        FireAppearanceTexture.applySnapshot(appearance, to: self)
        let summary = configuration.topicAiSummary
        isExpanded = configuration.isTopicAiSummaryExpanded && summary != nil
        let primaryInk = appearance.ink
        let secondaryInk = appearance.subtleInk
        let tertiaryInk = appearance.tertiaryInk
        titleNode.attributedText = NSAttributedString(
            string: "AI 摘要",
            attributes: [
                .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .subheadline, weight: .semibold),
                .foregroundColor: primaryInk,
            ]
        )
        if summary?.outdated == true {
            statusNode.attributedText = NSAttributedString(
                string: "有新回复",
                attributes: [
                    .font: FireTopicDetailRuntimeTypography.scaledFont(textStyle: .caption2, weight: .semibold),
                    .foregroundColor: FireTopicDetailCellColors.warning,
                ]
            )
            statusNode.backgroundColor = FireTopicDetailCellColors.warning.withAlphaComponent(0.12)
            statusNode.isHidden = false
        } else {
            statusNode.attributedText = nil
            statusNode.isHidden = true
        }
        let chevronName = isExpanded ? "chevron.up" : "chevron.down"
        chevronNode.image = UIImage(systemName: chevronName)?.withTintColor(
            tertiaryInk,
            renderingMode: .alwaysOriginal
        )
        if let summary, isExpanded {
            bodyNode.attributedText = NSAttributedString(
                string: summary.summarizedText,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: primaryInk,
                ]
            )
            bodyNode.isHidden = false
            let metadata = Self.metadata(for: summary)
            if !metadata.isEmpty {
                metadataNode.attributedText = NSAttributedString(
                    string: metadata.joined(separator: " · "),
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .caption2),
                        .foregroundColor: secondaryInk,
                    ]
                )
                metadataNode.isHidden = false
            } else {
                metadataNode.attributedText = nil
                metadataNode.isHidden = true
            }
        } else {
            bodyNode.attributedText = nil
            bodyNode.isHidden = true
            metadataNode.attributedText = nil
            metadataNode.isHidden = true
        }
        headerButtonNode.accessibilityLabel = isExpanded ? "收起 AI 摘要" : "展开 AI 摘要"
        setNeedsLayout()
    }
}
