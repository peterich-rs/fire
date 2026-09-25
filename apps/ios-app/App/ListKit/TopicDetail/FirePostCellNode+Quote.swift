import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    func configureQuote(payload: FirePostCellRenderPayload) {
        if let replyContext = payload.replyContext,
           let targetPN = payload.replyTargetPostNumber, targetPN > 0 {
            replyContextNode.isHidden = false
            let replyContextFont = UIFont.preferredFont(forTextStyle: .caption1)
            replyContextNode.setAttributedTitle(NSAttributedString(
                string: replyContext,
                attributes: [.font: replyContextFont, .foregroundColor: Self.accentTextColor]
            ), for: .normal)
        } else {
            replyContextNode.isHidden = true
            replyContextNode.setAttributedTitle(nil, for: .normal)
        }
    }
}
