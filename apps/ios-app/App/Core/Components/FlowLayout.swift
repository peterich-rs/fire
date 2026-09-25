import SwiftUI
import UIKit

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var fallbackWidth: CGFloat? = nil

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = resolvedMaxWidth(for: proposal)
        let hasExplicitWidth = proposal.width.map { $0.isFinite && $0 > 0 } ?? false
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + spacing
                maxLineWidth = max(maxLineWidth, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        totalHeight += lineHeight
        maxLineWidth = max(maxLineWidth, lineWidth)

        let reportedWidth = hasExplicitWidth ? maxWidth : maxLineWidth
        return CGSize(width: reportedWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var cursor = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > bounds.minX, cursor.x + size.width > bounds.maxX {
                cursor.x = bounds.minX
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: cursor,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func resolvedMaxWidth(for proposal: ProposedViewSize) -> CGFloat {
        if let proposalWidth = proposal.width, proposalWidth.isFinite, proposalWidth > 0 {
            return proposalWidth
        }

        if let fallbackWidth, fallbackWidth.isFinite, fallbackWidth > 0 {
            return fallbackWidth
        }

        return max(UIScreen.main.bounds.width - 120, 180)
    }
}
