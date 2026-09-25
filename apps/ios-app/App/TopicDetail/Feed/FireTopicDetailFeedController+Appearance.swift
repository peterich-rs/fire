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
            guard let node = collectionNode.nodeForItem(at: indexPath) as? FirePostCellNode else {
                continue
            }
            node.applyColorAppearance(resolved)
            node.invalidateCalculatedLayout()
            node.setNeedsLayout()
        }

        // Header / stats / footer Texture nodes are one-shot factories — reload so they
        // rebuild with the new resolved palette (and clear any black opaque fills).
        if !currentItems.isEmpty {
            collectionNode.reloadData()
        }
        // reloadData may recreate the scroll view hierarchy; re-assert shell after.
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
        if let layoutManager {
            layoutManager.updateTraitSignature(
                FirePostLayoutTraitSignature(
                    contentWidthPixels: Int(width.rounded(.toNearestOrEven)),
                    contentSizeCategory: UIApplication.shared.preferredContentSizeCategory.rawValue
                )
            )
        }
        if hadMeasuredWidth, !currentItems.isEmpty {
            collectionNode.reloadData()
        }
    }
}
