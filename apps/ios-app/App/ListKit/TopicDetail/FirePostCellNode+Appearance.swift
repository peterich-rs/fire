import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    func applyColorAppearance(_ appearance: FireAppearanceSnapshot) {
        guard let payload = currentPayload else {
            FireAppearanceTexture.applySnapshot(appearance, to: self)
            setNeedsDisplay()
            return
        }
        guard payload.appearance.token != appearance.token else {
            // Already baked for this appearance; still refresh canvas in case highlight state moved.
            configureSearchHighlight(payload.isSearchHighlighted)
            return
        }
        let updated = payload.withAppearance(appearance)
        currentPayload = updated
        // Force text rebind when appearance flips, but keep `contentSegmentSignature` so
        // FirePostImageNode instances are not destroyed mid-load (blank image placeholders).
        renderedContentID = nil
        configureMeta(payload: updated)
        configureBodyContent(payload: updated)
        configureReplyShortcut(payload: updated)
        configureOverflowActions(payload: updated)
        configureReactionPicker(payload: updated)
        configureReactions(payload: updated)
        configureSearchHighlight(updated.isSearchHighlighted)
        setNeedsDisplay()
    }

    func applyColorAppearance(_ colorTraits: UITraitCollection) {
        applyColorAppearance(FireAppearanceEnvironment.snapshot(traits: colorTraits))
    }

    func refreshResolvedColorsFromLiveTraitsIfNeeded() {
        guard isNodeLoaded, currentPayload != nil else { return }
        applyColorAppearance(FireAppearanceEnvironment.snapshot(for: view))
    }
}
