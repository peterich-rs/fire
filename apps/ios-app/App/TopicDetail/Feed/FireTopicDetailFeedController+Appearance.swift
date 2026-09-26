import AsyncDisplayKit
import UIKit

@MainActor
extension FireTopicDetailFeedController {
    func layoutContentWidth(proposedWidth: CGFloat? = nil) -> CGFloat {
        let adjustedBoundsWidth = collectionNode.view.bounds.width
            - collectionNode.view.adjustedContentInset.left
            - collectionNode.view.adjustedContentInset.right
        if adjustedBoundsWidth > 0 {
            return adjustedBoundsWidth
        }
        return max(proposedWidth ?? collectionNode.view.bounds.width, 1)
    }

    /// Trait collection used to bake Texture text colors. Prefer the loaded
    /// collection view so window `overrideUserInterfaceStyle` is respected.
    func currentColorTraits() -> UITraitCollection {
        if collectionNode.isNodeLoaded {
            return FireAppearanceEnvironment.traits(for: collectionNode.view)
        }
        return FireAppearanceEnvironment.traits()
    }

    func currentAppearanceSnapshot() -> FireAppearanceSnapshot {
        if collectionNode.isNodeLoaded {
            return FireAppearanceEnvironment.snapshot(for: collectionNode.view)
        }
        return FireAppearanceEnvironment.snapshot()
    }

    /// Re-assert collection + scroll-view canvas from the current snapshot.
    /// Must run after theme flips **and** after data reloads (PTR) so pure-black
    /// Texture shells cannot survive a light switch.
    func assertFeedShellAppearance(_ snapshot: FireAppearanceSnapshot? = nil) {
        let resolved = snapshot ?? currentAppearanceSnapshot()
        FireAppearanceTexture.applyCanvas(resolved.canvas, to: collectionNode)
        if collectionNode.isNodeLoaded {
            FireAppearanceTexture.applyCanvas(resolved.canvas, to: collectionNode.view)
            collectionNode.view.refreshControl?.tintColor = resolved.subtleInk
        }
    }

    /// Full color-appearance refresh after light/dark (or OLED) changes.
    /// Rebuilds chrome + re-bakes visible post cells; reloads so factory ASTextNodes
    /// also pick up resolved ink tokens.
    func refreshColorAppearance(_ snapshot: FireAppearanceSnapshot? = nil) {
        let resolved = snapshot ?? currentAppearanceSnapshot()
        assertFeedShellAppearance(resolved)

        for indexPath in visibleIndexPaths {
            guard let node = collectionNode.nodeForItem(at: indexPath) else { continue }
            if let postNode = node as? FirePostCellNode {
                postNode.applyColorAppearance(resolved)
            } else if let chrome = node as? FireTopicDetailChromeCellNode,
                      indexPath.item < currentItems.count,
                      let configuration = currentConfiguration {
                chrome.apply(
                    item: currentItems[indexPath.item],
                    configuration: configuration,
                    appearance: resolved
                )
            }
        }
        assertFeedShellAppearance(resolved)
    }

    func invalidateLayoutIfWidthChanged() {
        let width = layoutContentWidth()
        guard width > 1 else { return }
        if let lastLayoutContentWidth,
           abs(lastLayoutContentWidth - width) < 0.5 {
            return
        }
        let hadMeasuredWidth = lastLayoutContentWidth != nil
        lastLayoutContentWidth = width
        collectionNode.view.collectionViewLayout.invalidateLayout()
        if hadMeasuredWidth, !currentItems.isEmpty {
            collectionNode.relayoutItems()
        }
    }
}
