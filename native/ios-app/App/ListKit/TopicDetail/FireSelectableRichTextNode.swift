import AsyncDisplayKit
import UIKit

final class FireSelectableRichTextNode: ASDisplayNode, UITextViewDelegate {
    var attributedText: NSAttributedString? {
        didSet {
            applyText()
            setNeedsLayout()
        }
    }

    var onLink: ((URL) -> Void)?
    private var richTextView: UITextView?

    override init() {
        super.init()
        isUserInteractionEnabled = true
        style.flexShrink = 1.0
    }

    override func didLoad() {
        super.didLoad()
        let textView = FireRichTextTextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.adjustsFontForContentSizeCategory = true
        textView.dataDetectorTypes = []
        textView.delegate = self
        textView.frame = bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(textView)
        richTextView = textView
        applyText()
    }

    override func layout() {
        super.layout()
        richTextView?.frame = bounds
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        guard let attributedText, attributedText.length > 0 else {
            return .zero
        }
        let width = max(constrainedSize.width, 1)
        let bounds = attributedText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CGSize(width: width, height: max(ceil(bounds.height), 1))
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        onLink?(URL)
        return false
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange
    ) -> Bool {
        onLink?(URL)
        return false
    }

    private func applyText() {
        guard isNodeLoaded else {
            return
        }
        let text = attributedText
        let apply = { [weak self] in
            guard let self else { return }
            self.richTextView?.attributedText = text
            (self.richTextView as? FireRichTextTextView)?.refreshQuotePreviewLayers()
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}
