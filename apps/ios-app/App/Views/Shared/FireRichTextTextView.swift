import UIKit

extension NSAttributedString.Key {
    static let fireQuotePreviewBlock = NSAttributedString.Key("FireQuotePreviewBlock")
    static let fireQuotePreviewBackgroundColor = NSAttributedString.Key("FireQuotePreviewBackgroundColor")
    static let fireQuotePreviewStripeColor = NSAttributedString.Key("FireQuotePreviewStripeColor")
}

class FireRichTextTextView: UITextView {
    private var quotePreviewLayers: [CALayer] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        updateQuotePreviewLayers()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateQuotePreviewLayers()
    }

    func refreshQuotePreviewLayers() {
        updateQuotePreviewLayers()
    }

    private func updateQuotePreviewLayers() {
        quotePreviewLayers.forEach { $0.removeFromSuperlayer() }
        quotePreviewLayers.removeAll()

        guard let attributedText,
              attributedText.length > 0,
              bounds.width > 1 else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttribute(.fireQuotePreviewBlock, in: fullRange) { [weak self] value, range, _ in
            guard let self, value != nil else {
                return
            }
            self.addQuotePreviewLayer(for: range, attributedText: attributedText)
        }
    }

    private func addQuotePreviewLayer(for characterRange: NSRange, attributedText: NSAttributedString) {
        guard characterRange.length > 0 else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else {
            return
        }

        var unionRect = CGRect.null
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            guard NSIntersectionRange(glyphRange, lineGlyphRange).length > 0 else {
                return
            }
            let lineRect = CGRect(
                x: self.textContainerInset.left,
                y: self.textContainerInset.top + usedRect.minY - self.contentOffset.y,
                width: max(self.bounds.width - self.textContainerInset.left - self.textContainerInset.right, 1),
                height: usedRect.height
            )
            unionRect = unionRect.isNull ? lineRect : unionRect.union(lineRect)
        }

        guard !unionRect.isNull else {
            return
        }

        let backgroundColor = attributedText.attribute(
            .fireQuotePreviewBackgroundColor,
            at: characterRange.location,
            effectiveRange: nil
        ) as? UIColor ?? .secondarySystemBackground
        let stripeColor = attributedText.attribute(
            .fireQuotePreviewStripeColor,
            at: characterRange.location,
            effectiveRange: nil
        ) as? UIColor ?? .tertiaryLabel

        // Background tracks layout glyphs (padding lines already baked into text).
        let backgroundRect = CGRect(
            x: textContainerInset.left,
            y: unionRect.minY - 2,
            width: max(bounds.width - textContainerInset.left - textContainerInset.right, 1),
            height: unionRect.height + 4
        ).intersection(bounds.insetBy(dx: 0, dy: -2))
        guard !backgroundRect.isNull, backgroundRect.height > 1 else {
            return
        }

        let backgroundLayer = CAShapeLayer()
        backgroundLayer.fillColor = backgroundColor.resolvedColor(with: traitCollection).cgColor
        backgroundLayer.path = UIBezierPath(
            roundedRect: backgroundRect,
            cornerRadius: 8
        ).cgPath
        layer.insertSublayer(backgroundLayer, at: 0)
        quotePreviewLayers.append(backgroundLayer)

        // Left accent bar (blockquote border-left).
        let stripeRect = CGRect(
            x: backgroundRect.minX + 8,
            y: backgroundRect.minY + 8,
            width: 4,
            height: max(backgroundRect.height - 16, 1)
        )
        let stripeLayer = CAShapeLayer()
        stripeLayer.fillColor = stripeColor.resolvedColor(with: traitCollection).cgColor
        stripeLayer.path = UIBezierPath(
            roundedRect: stripeRect,
            cornerRadius: 2
        ).cgPath
        layer.insertSublayer(stripeLayer, above: backgroundLayer)
        quotePreviewLayers.append(stripeLayer)
    }
}

/// Custom UITextView that sizes itself to content.
final class FireRichTextUIView: FireRichTextTextView {
    private static let intrinsicHeightCache = NSCache<NSString, NSNumber>()

    var renderedContentID: String?
    private var emojiLoadTasks: [String: Task<Void, Never>] = [:]
    private var measuredWidth: CGFloat = 0
    private var cachedIntrinsicHeight: CGFloat?

    deinit {
        cancelEmojiLoadTasks()
    }

    override var attributedText: NSAttributedString! {
        didSet {
            resetIntrinsicMeasurement()
            cancelEmojiLoadTasks()
            loadEmojiAttachmentsIfNeeded()
            refreshQuotePreviewLayers()
        }
    }

    override var intrinsicContentSize: CGSize {
        let width = resolvedMeasurementWidth()
        if let cachedIntrinsicHeight, abs(width - measuredWidth) < 0.5 {
            return CGSize(width: UIView.noIntrinsicMetric, height: cachedIntrinsicHeight)
        }

        if let renderedContentID,
           let cachedHeight = Self.intrinsicHeightCache.object(
               forKey: intrinsicHeightCacheKey(contentID: renderedContentID, width: width)
           ) {
            measuredWidth = width
            cachedIntrinsicHeight = CGFloat(truncating: cachedHeight)
            return CGSize(width: UIView.noIntrinsicMetric, height: CGFloat(truncating: cachedHeight))
        }

        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let resolvedHeight = ceil(size.height)
        measuredWidth = width
        cachedIntrinsicHeight = resolvedHeight
        if let renderedContentID {
            Self.intrinsicHeightCache.setObject(
                NSNumber(value: resolvedHeight),
                forKey: intrinsicHeightCacheKey(contentID: renderedContentID, width: width)
            )
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: resolvedHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = resolvedMeasurementWidth()
        if abs(width - measuredWidth) >= 0.5 {
            cachedIntrinsicHeight = nil
            invalidateIntrinsicContentSize()
        }
    }

    private func resolvedMeasurementWidth() -> CGFloat {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 80
        return max(width, 1)
    }

    private func cancelEmojiLoadTasks() {
        emojiLoadTasks.values.forEach { $0.cancel() }
        emojiLoadTasks.removeAll()
    }

    private func resetIntrinsicMeasurement() {
        measuredWidth = 0
        cachedIntrinsicHeight = nil
    }

    private func intrinsicHeightCacheKey(contentID: String, width: CGFloat) -> NSString {
        let scaledWidth = Int((width * UIScreen.main.scale).rounded())
        return "\(contentID)|w:\(scaledWidth)" as NSString
    }

    private func loadEmojiAttachmentsIfNeeded() {
        guard attributedText.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttribute(.attachment, in: fullRange) { [weak self] value, _, _ in
            guard let self,
                  let attachment = value as? FireRichTextEmojiAttachment else {
                return
            }

            let cacheKey = attachment.cacheKey
            guard emojiLoadTasks[cacheKey] == nil else {
                return
            }

            if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: attachment.request) {
                applyEmojiImage(cachedImage, for: cacheKey)
                return
            }

            emojiLoadTasks[cacheKey] = Task { [weak self] in
                do {
                    let image = try await FireRemoteImagePipeline.shared.loadImage(for: attachment.request)
                    guard !Task.isCancelled else {
                        return
                    }
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        self.applyEmojiImage(image, for: cacheKey)
                        self.emojiLoadTasks.removeValue(forKey: cacheKey)
                    }
                } catch {
                    await MainActor.run {
                        _ = self?.emojiLoadTasks.removeValue(forKey: cacheKey)
                    }
                }
            }
        }
    }

    private func applyEmojiImage(_ image: UIImage, for cacheKey: String) {
        guard textStorage.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        var changedRange = NSRange(location: NSNotFound, length: 0)
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? FireRichTextEmojiAttachment,
                  attachment.cacheKey == cacheKey else {
                return
            }
            attachment.applyLoadedImage(image)
            textStorage.addAttribute(.attachment, value: attachment, range: range)
            changedRange = changedRange.location == NSNotFound
                ? range
                : NSUnionRange(changedRange, range)
        }
        textStorage.endEditing()

        guard changedRange.location != NSNotFound else {
            return
        }

        layoutManager.invalidateDisplay(forCharacterRange: changedRange)
        setNeedsLayout()
    }
}
