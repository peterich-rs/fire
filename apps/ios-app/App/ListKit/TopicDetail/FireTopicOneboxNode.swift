import AsyncDisplayKit
import UIKit

/// Discourse onebox card: site icon and domain on top, thumbnail beside title/description.
/// The favicon must stay a 16pt chrome mark — it is not a post image.
final class FireTopicOneboxNode: ASControlNode {
    var onOpen: ((URL) -> Void)?

    private let card: FireTopicOneboxCard
    private let iconNode = ASImageNode()
    private let thumbnailNode = ASImageNode()
    private let sourceNode = ASTextNode()
    private let titleNode = ASTextNode()
    private let descriptionNode = ASTextNode()
    private var iconTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?

    init(card: FireTopicOneboxCard) {
        self.card = card
        super.init()
        automaticallyManagesSubnodes = true
        isUserInteractionEnabled = card.url.flatMap(URL.init(string:)) != nil
        clipsToBounds = true
        cornerRadius = 10
        borderWidth = 1 / UIScreen.main.scale
        addTarget(self, action: #selector(handleOpen), forControlEvents: .touchUpInside)

        iconNode.contentMode = .scaleAspectFit
        iconNode.clipsToBounds = true
        iconNode.cornerRadius = 3
        iconNode.isLayerBacked = true
        iconNode.isHidden = card.iconURL == nil

        thumbnailNode.contentMode = .scaleAspectFill
        thumbnailNode.clipsToBounds = true
        thumbnailNode.cornerRadius = 6
        thumbnailNode.isLayerBacked = true
        thumbnailNode.backgroundColor = .tertiarySystemFill
        thumbnailNode.isHidden = card.thumbnailURL == nil

        configureTextNodes()
        refreshChrome()
        accessibilityLabel = [card.sourceName, card.title].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = isUserInteractionEnabled ? [.button, .link] : .staticText
    }

    func refreshChrome() {
        backgroundColor = FireTheme.uiSurface
        borderColor = FireTheme.uiChromeBorder.cgColor
        configureTextNodes()
    }

    override func didLoad() {
        super.didLoad()
        loadRemoteImage(card.iconURL, into: iconNode, task: &iconTask, hideOnFailure: true)
        loadRemoteImage(card.thumbnailURL, into: thumbnailNode, task: &thumbnailTask, hideOnFailure: false)
    }

    override func asyncTraitCollectionDidChange(
        withPreviousTraitCollection previousTraitCollection: ASPrimitiveTraitCollection
    ) {
        super.asyncTraitCollectionDidChange(withPreviousTraitCollection: previousTraitCollection)
        refreshChrome()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        var rows: [ASLayoutElement] = []
        if sourceRowVisible {
            iconNode.style.preferredSize = CGSize(width: 16, height: 16)
            iconNode.style.flexShrink = 0
            sourceNode.style.flexShrink = 1
            sourceNode.style.flexGrow = 1
            var sourceChildren: [ASLayoutElement] = []
            if !iconNode.isHidden {
                sourceChildren.append(iconNode)
            }
            if !sourceNode.isHidden {
                sourceChildren.append(sourceNode)
            }
            if !sourceChildren.isEmpty {
                let sourceRow = ASStackLayoutSpec(
                    direction: .horizontal,
                    spacing: 6,
                    justifyContent: .start,
                    alignItems: .center,
                    children: sourceChildren
                )
                rows.append(sourceRow)
            }
        }

        var bodyChildren: [ASLayoutElement] = []
        if !thumbnailNode.isHidden {
            let size = thumbnailDisplaySize
            thumbnailNode.style.preferredSize = size
            thumbnailNode.style.flexShrink = 0
            bodyChildren.append(thumbnailNode)
        }

        let textChildren = [titleNode, descriptionNode].filter { !$0.isHidden }
        if !textChildren.isEmpty {
            let textColumn = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 4,
                justifyContent: .start,
                alignItems: .stretch,
                children: textChildren
            )
            textColumn.style.flexShrink = 1
            textColumn.style.flexGrow = 1
            bodyChildren.append(textColumn)
        }

        if !bodyChildren.isEmpty {
            let body = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 10,
                justifyContent: .start,
                alignItems: .start,
                children: bodyChildren
            )
            rows.append(body)
        }

        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8,
            justifyContent: .start,
            alignItems: .stretch,
            children: rows
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10),
            child: stack
        )
    }

    private var sourceRowVisible: Bool {
        let source = card.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !source.isEmpty || card.iconURL != nil
    }

    private var thumbnailDisplaySize: CGSize {
        let maxWidth: CGFloat = 112
        let maxHeight: CGFloat = 84
        let sourceWidth = card.thumbnailWidth ?? 0
        let sourceHeight = card.thumbnailHeight ?? 0
        let aspect = sourceWidth > 0 && sourceHeight > 0 ? sourceWidth / sourceHeight : 16.0 / 9.0
        var width = maxWidth
        var height = width / max(aspect, 0.01)
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    private func configureTextNodes() {
        let source = card.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sourceNode.maximumNumberOfLines = 1
        sourceNode.truncationMode = .byTruncatingTail
        sourceNode.isHidden = source.isEmpty
        sourceNode.attributedText = NSAttributedString(
            string: source,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: FireTheme.uiSubtleInk,
            ]
        )

        let title = card.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        titleNode.maximumNumberOfLines = 3
        titleNode.truncationMode = .byTruncatingTail
        titleNode.isHidden = title.isEmpty
        let titleFont = UIFont.preferredFont(forTextStyle: .subheadline)
        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: titleFont.pointSize, weight: .semibold),
                .foregroundColor: FireTheme.uiAccent,
            ]
        )

        let description = card.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        descriptionNode.maximumNumberOfLines = 0
        descriptionNode.truncationMode = .byTruncatingTail
        descriptionNode.isHidden = description.isEmpty
        descriptionNode.attributedText = NSAttributedString(
            string: description,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: FireTheme.uiSubtleInk,
            ]
        )
    }

    private func loadRemoteImage(
        _ url: URL?,
        into imageNode: ASImageNode,
        task: inout Task<Void, Never>?,
        hideOnFailure: Bool
    ) {
        task?.cancel()
        task = nil
        guard let url else {
            imageNode.image = nil
            imageNode.isHidden = true
            return
        }
        let request = FireRemoteImageRequest(url: url)
        if let cached = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            imageNode.image = cached
            imageNode.isHidden = false
            return
        }
        task = Task { [weak self, weak imageNode] in
            do {
                let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    imageNode?.image = image
                    imageNode?.isHidden = false
                    self?.setNeedsLayout()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if hideOnFailure {
                        imageNode?.isHidden = true
                        self?.setNeedsLayout()
                    }
                }
            }
        }
    }

    @objc private func handleOpen() {
        guard let url = card.url.flatMap(URL.init(string:)) else { return }
        onOpen?(url)
    }
}
