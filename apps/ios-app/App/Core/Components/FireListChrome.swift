import SwiftUI
import UIKit

extension View {
    func fireHiddenListBackground() -> some View {
        background(FireListBackgroundClearer())
    }
}

private struct FireListBackgroundClearer: UIViewRepresentable {
    func makeUIView(context: Context) -> FireListBackgroundClearerView {
        FireListBackgroundClearerView()
    }

    func updateUIView(_ view: FireListBackgroundClearerView, context: Context) {
        view.clearEnclosingListBackground()
    }
}

final class FireListBackgroundClearerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        clearEnclosingListBackground()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clearEnclosingListBackground()
    }

    func clearEnclosingListBackground() {
        var current: UIView? = superview
        while let view = current {
            if let table = view as? UITableView {
                table.backgroundColor = .clear
                if table.backgroundView == nil {
                    table.backgroundView = UIView()
                }
                table.backgroundView?.backgroundColor = .clear
            }
            if let collection = view as? UICollectionView {
                collection.backgroundColor = .clear
            }
            current = view.superview
        }
    }
}
