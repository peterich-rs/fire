import AsyncDisplayKit
import UIKit

final class FirePostRichTextContainerView: UIView {
    private let textNode = ASTextNode()
    private var linkDelegate: RichTextLinkDelegate?
    private var renderedContentID: String?

    var onLinkTapped: ((URL) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        linkDelegate = RichTextLinkDelegate(handler: { [weak self] url in
            self?.onLinkTapped?(url)
        })
        textNode.delegate = linkDelegate
        textNode.isUserInteractionEnabled = true
        textNode.backgroundColor = .clear
        textNode.linkAttributeNames = [NSAttributedString.Key.link.rawValue]
        textNode.placeholderEnabled = true
        textNode.placeholderColor = .tertiarySystemFill

        addSubview(textNode.view)
    }

    func configure(
        attributedText: NSAttributedString,
        contentID: String,
        containerSize: CGSize
    ) {
        if renderedContentID != contentID {
            renderedContentID = contentID
            textNode.attributedText = attributedText
        }
        textNode.frame = CGRect(origin: .zero, size: CGSize(width: containerSize.width, height: containerSize.height))
    }

    func resetContent() {
        renderedContentID = nil
        textNode.attributedText = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textNode.frame = bounds
    }
}

private final class RichTextLinkDelegate: NSObject, ASTextNodeDelegate {
    private let handler: (URL) -> Void

    init(handler: @escaping (URL) -> Void) {
        self.handler = handler
    }

    func textNode(
        _ textNode: ASTextNode,
        tappedLinkAttribute attribute: String,
        value: Any,
        at point: CGPoint,
        textRange: NSRange
    ) {
        if let url = value as? URL {
            handler(url)
        } else if let string = value as? String, let url = URL(string: string) {
            handler(url)
        }
    }
}
