import AsyncDisplayKit
import UIKit

/// Root Texture node for the topic-detail page.
///
/// Owns:
/// - The `ASCollectionNode` feed surface (placeholder container in Task 1 skeleton)
/// - Bottom chrome layout (quick reply bar will be added in Task 6)
///
/// Layout is performed by Texture on a background thread.
final class FireTopicDetailRootNode: ASDisplayNode {

    // MARK: - Feed Container (placeholder, wired in Task 4)

    private let feedContainerNode: ASDisplayNode = {
        let node = ASDisplayNode()
        node.backgroundColor = .systemBackground
        node.style.flexGrow = 1.0
        node.style.flexShrink = 1.0
        return node
    }()

    // MARK: - Init

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .systemBackground
    }

    // MARK: - Layout

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: [feedContainerNode]
        )
        stack.style.flexGrow = 1.0
        stack.style.flexShrink = 1.0
        return ASWrapperLayoutSpec(layoutElement: stack)
    }
}
