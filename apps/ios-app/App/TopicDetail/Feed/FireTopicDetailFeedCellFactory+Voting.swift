import AsyncDisplayKit
import UIKit

extension FireTopicDetailFeedCellFactory {
    @objc
    private func handleToggleTopicVote() {
        guard let configuration else { return }
        Task { await configuration.onToggleTopicVote() }
    }

    @objc
    private func handleShowTopicVoters() {
        guard let configuration else { return }
        Task { await configuration.onShowTopicVoters() }
    }

    func makeTopicVoteCellNode(
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) -> ASCellNode {
        guard let detail = configuration.detail else { return ASCellNode() }

        let wrapperNode = ASCellNode()
        wrapperNode.automaticallyManagesSubnodes = true
        FireAppearanceTexture.applySnapshot(appearance, to: wrapperNode)

        let containerNode = ASDisplayNode()
        containerNode.backgroundColor = .secondarySystemBackground
        containerNode.cornerRadius = 8
        containerNode.automaticallyManagesSubnodes = true

        let titleNode = ASTextNode()
        FireAppearanceTexture.configureChromeTextNode(titleNode)
        titleNode.attributedText = NSAttributedString(
            string: "\(detail.voteCount) 票",
            attributes: [
                .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                    for: UIFont.systemFont(
                        ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                        weight: .semibold
                    )
                ),
                .foregroundColor: FireTopicDetailCellColors.accent,
            ]
        )

        let statusNode = ASTextNode()
        FireAppearanceTexture.configureChromeTextNode(statusNode)
        if detail.userVoted {
            statusNode.attributedText = NSAttributedString(
                string: "你已投票",
                attributes: [
                    .font: UIFontMetrics(forTextStyle: .caption1).scaledFont(
                        for: UIFont.systemFont(
                            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                            weight: .semibold
                        )
                    ),
                    .foregroundColor: UIColor.systemGreen,
                ]
            )
        }
        statusNode.isHidden = !detail.userVoted
        statusNode.style.flexShrink = 1.0

        let toggleNode = ASButtonNode()
        toggleNode.setTitle(
            detail.userVoted ? "取消投票" : "投一票",
            with: UIFont.preferredFont(forTextStyle: .caption1),
            with: detail.userVoted ? appearance.ink : .white,
            for: .normal
        )
        toggleNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        toggleNode.backgroundColor = detail.userVoted ? .tertiarySystemFill : FireTopicDetailCellColors.accent
        toggleNode.cornerRadius = 16
        toggleNode.clipsToBounds = true
        toggleNode.isEnabled = configuration.canWriteInteractions
        toggleNode.addTarget(self, action: #selector(handleToggleTopicVote), forControlEvents: .touchUpInside)
        toggleNode.fireBindPressBounce(.button)

        let votersNode = ASButtonNode()
        votersNode.setImage(UIImage(systemName: "person.3"), for: .normal)
        votersNode.setTitle(
            "查看投票用户",
            with: UIFont.preferredFont(forTextStyle: .caption1),
            with: FireTopicDetailCellColors.accent,
            for: .normal
        )
        votersNode.contentSpacing = 6
        votersNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        votersNode.addTarget(self, action: #selector(handleShowTopicVoters), forControlEvents: .touchUpInside)
        votersNode.fireBindPressBounce(.compact)

        containerNode.layoutSpecBlock = { _, _ in
            let spacer = ASLayoutSpec()
            spacer.style.flexGrow = 1.0
            let headerChildren: [ASLayoutElement] = detail.userVoted
                ? [titleNode, spacer, statusNode]
                : [titleNode, spacer]
            let headerRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 10,
                justifyContent: .start,
                alignItems: .center,
                children: headerChildren
            )
            let buttonRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 10,
                justifyContent: .start,
                alignItems: .center,
                children: [toggleNode, votersNode]
            )
            let innerStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 10,
                justifyContent: .start,
                alignItems: .stretch,
                children: [headerRow, buttonRow]
            )
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14),
                child: innerStack
            )
        }

        wrapperNode.layoutSpecBlock = { _, _ in
            ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 8, left: 16, bottom: 4, right: 16),
                child: containerNode
            )
        }
        return wrapperNode
    }
}

final class FireTopicDetailVoteChromeNode: ASCellNode, FireTopicDetailChromeCellNode {
    private let containerNode = ASDisplayNode()
    private let titleNode = ASTextNode()
    private let statusNode = ASTextNode()
    private let toggleNode = ASButtonNode()
    private let votersNode = ASButtonNode()
    private var onToggle: (() async -> Void)?
    private var onShowVoters: (() async -> Void)?

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        containerNode.automaticallyManagesSubnodes = true
        containerNode.backgroundColor = .secondarySystemBackground
        containerNode.cornerRadius = 8
        FireAppearanceTexture.configureChromeTextNode(titleNode)
        FireAppearanceTexture.configureChromeTextNode(statusNode)
        toggleNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        toggleNode.cornerRadius = 16
        toggleNode.clipsToBounds = true
        toggleNode.addTarget(self, action: #selector(handleToggle), forControlEvents: .touchUpInside)
        toggleNode.fireBindPressBounce(.button)
        votersNode.contentSpacing = 6
        votersNode.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        votersNode.addTarget(self, action: #selector(handleVoters), forControlEvents: .touchUpInside)
        votersNode.fireBindPressBounce(.compact)
    }

    func apply(
        item _: FireTopicDetailRuntimeItem,
        configuration: FireTopicDetailRuntimeConfiguration,
        appearance: FireAppearanceSnapshot
    ) {
        FireAppearanceTexture.applySnapshot(appearance, to: self)
        guard let detail = configuration.detail else {
            titleNode.attributedText = nil
            statusNode.isHidden = true
            setNeedsLayout()
            return
        }
        titleNode.attributedText = NSAttributedString(
            string: "\(detail.voteCount) 票",
            attributes: [
                .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                    for: UIFont.systemFont(
                        ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                        weight: .semibold
                    )
                ),
                .foregroundColor: FireTopicDetailCellColors.accent,
            ]
        )
        statusNode.attributedText = NSAttributedString(
            string: "你已投票",
            attributes: [
                .font: UIFontMetrics(forTextStyle: .caption1).scaledFont(
                    for: UIFont.systemFont(
                        ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                        weight: .semibold
                    )
                ),
                .foregroundColor: UIColor.systemGreen,
            ]
        )
        statusNode.isHidden = !detail.userVoted
        toggleNode.setTitle(
            detail.userVoted ? "取消投票" : "投一票",
            with: UIFont.preferredFont(forTextStyle: .caption1),
            with: detail.userVoted ? appearance.ink : .white,
            for: .normal
        )
        toggleNode.backgroundColor = detail.userVoted ? .tertiarySystemFill : FireTopicDetailCellColors.accent
        toggleNode.isEnabled = configuration.canWriteInteractions
        votersNode.setImage(UIImage(systemName: "person.3"), for: .normal)
        votersNode.setTitle(
            "查看投票用户",
            with: UIFont.preferredFont(forTextStyle: .caption1),
            with: FireTopicDetailCellColors.accent,
            for: .normal
        )
        onToggle = configuration.onToggleTopicVote
        onShowVoters = configuration.onShowTopicVoters
        setNeedsLayout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1.0
        var headerChildren: [ASLayoutElement] = [titleNode, spacer]
        if !statusNode.isHidden {
            headerChildren.append(statusNode)
        }
        let headerRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10,
            justifyContent: .start,
            alignItems: .center,
            children: headerChildren
        )
        let buttonRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10,
            justifyContent: .start,
            alignItems: .center,
            children: [toggleNode, votersNode]
        )
        let inner = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 10,
            justifyContent: .start,
            alignItems: .stretch,
            children: [headerRow, buttonRow]
        )
        let padded = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14),
            child: inner
        )
        let card = ASBackgroundLayoutSpec(child: padded, background: containerNode)
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8, left: 16, bottom: 4, right: 16),
            child: card
        )
    }

    @objc private func handleToggle() {
        Task { await onToggle?() }
    }

    @objc private func handleVoters() {
        Task { await onShowVoters?() }
    }
}
