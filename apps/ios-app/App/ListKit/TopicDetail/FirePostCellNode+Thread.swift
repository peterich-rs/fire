import AsyncDisplayKit
import UIKit

extension FirePostCellNode {
    func configureThreadLine(shows: Bool) {
        threadLineNode.isHidden = !shows
        threadLineNode.style.preferredSize = CGSize(width: 1, height: shows ? 1 : 0)
        threadLineNode.style.flexGrow = shows ? 1.0 : 0.0
    }

    func configureDivider(shows: Bool) {
        dividerNode.isHidden = !shows
    }
}
