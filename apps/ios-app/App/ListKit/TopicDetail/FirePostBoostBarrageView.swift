import AsyncDisplayKit
import UIKit

// MARK: - Boost Animation Helpers

enum FirePostBoostLayerAnimator {
    static func pause(_ layers: [CALayer]) {
        for layer in layers where layer.speed != 0 {
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
        }
    }

    static func resume(_ layers: [CALayer]) {
        for layer in layers where layer.speed == 0 {
            let pausedTime = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            let elapsed = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            layer.beginTime = elapsed
        }
    }

    static func hasPausedAnimation(_ layers: [CALayer]) -> Bool {
        layers.contains { $0.speed == 0 }
    }

    static func hasAnimation(_ layers: [CALayer]) -> Bool {
        layers.contains { !($0.animationKeys() ?? []).isEmpty }
    }

    static func resetTiming(_ layers: [CALayer]) {
        for layer in layers {
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
        }
    }

    static func stableHash(text: String?, index: Int) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in (text ?? "").utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        hash ^= UInt32(index & 0xFFFF)
        return hash
    }
}

// MARK: - Boost Barrage

final class FirePostBoostBarrageView: UIView {
    private static let maximumLaneCount = 5
    private static let chipHeight: CGFloat = FirePostCellLayoutCalculator.fixedBoostManualRowHeight
    private static let minimumLaneGap: CGFloat = 4
    private static var displayedBatchSignatures: Set<String> = []

    private var chips: [FirePostBoostChipView] = []
    private var signature: String = ""
    private var batchSignature: String = ""
    private var lastAnimatedBounds: CGRect = .null
    private var animationsEnabled = true
    private var animationRunID: UInt64 = 0
    private var pendingAnimationCompletionCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        boosts: [TopicPostBoostState],
        batchSignature: String,
        animationsEnabled: Bool,
        baseURLString: String
    ) {
        let visibleBoosts = boosts.filter {
            !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let isCurrentActiveBatch = batchSignature == self.batchSignature && !chips.isEmpty
        guard !batchSignature.isEmpty,
              !Self.displayedBatchSignatures.contains(batchSignature) || isCurrentActiveBatch else {
            signature = ""
            self.batchSignature = batchSignature
            removeAllLabels()
            isHidden = true
            return
        }
        let nextSignature = visibleBoosts.map(FirePostBoostDisplay.contentSignature(for:)).joined(separator: "\u{1E}")
        guard nextSignature != signature || batchSignature != self.batchSignature else {
            isHidden = visibleBoosts.isEmpty
            setAnimationsEnabled(animationsEnabled)
            return
        }

        self.animationsEnabled = animationsEnabled
        signature = nextSignature
        self.batchSignature = batchSignature
        chips.forEach { chip in
            chip.layer.removeAllAnimations()
            chip.removeFromSuperview()
        }
        chips.removeAll()
        isHidden = visibleBoosts.isEmpty

        for boost in visibleBoosts {
            let chip = FirePostBoostChipView.styleForBarrage()
            chip.configure(
                boost: boost,
                attributedText: FirePostBoostDisplay.compactChipContent(
                    for: boost,
                    textColor: FireTheme.uiInk
                ),
                signature: FirePostBoostDisplay.contentSignature(for: boost),
                baseURLString: baseURLString
            )
            addSubview(chip)
            chips.append(chip)
        }
        restartLayoutAndAnimations()
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        guard animationsEnabled != enabled else { return }
        animationsEnabled = enabled
        if enabled {
            let layers = chips.map(\.layer)
            if FirePostBoostLayerAnimator.hasPausedAnimation(layers),
               FirePostBoostLayerAnimator.hasAnimation(layers) {
                FirePostBoostLayerAnimator.resume(layers)
            } else if !FirePostBoostLayerAnimator.hasAnimation(layers) {
                FirePostBoostLayerAnimator.resetTiming(layers)
                restartLayoutAndAnimations()
            }
        } else {
            FirePostBoostLayerAnimator.pause(chips.map(\.layer))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLabelsAndStartAnimationIfNeeded()
    }

    private func layoutLabelsAndStartAnimationIfNeeded() {
        guard !chips.isEmpty,
              bounds.width > 1,
              bounds.height > 1,
              lastAnimatedBounds != bounds else {
            return
        }
        lastAnimatedBounds = bounds

        let availableLaneCount = max(
            1,
            min(
                Self.maximumLaneCount,
                Int((bounds.height + Self.minimumLaneGap) / (Self.chipHeight + Self.minimumLaneGap))
            )
        )
        let laneCount = max(1, min(chips.count, availableLaneCount))
        let maxChipWidth = max(bounds.width * 0.72, 1)
        let shouldAnimate = animationsEnabled && !UIAccessibility.isReduceMotionEnabled
        let laneStep = laneCount > 1
            ? max((bounds.height - Self.chipHeight) / CGFloat(laneCount - 1), Self.minimumLaneGap)
            : 0
        let runID: UInt64
        if shouldAnimate {
            animationRunID &+= 1
            runID = animationRunID
            pendingAnimationCompletionCount = chips.count
            Self.displayedBatchSignatures.insert(batchSignature)
        } else {
            runID = animationRunID
            pendingAnimationCompletionCount = 0
        }

        for (index, chip) in chips.enumerated() {
            chip.layer.removeAllAnimations()
            chip.transform = .identity
            let measured = chip.sizeThatFits(CGSize(width: maxChipWidth, height: Self.chipHeight))
            let chipWidth = min(max(measured.width, 48), maxChipWidth)
            let lane = index % laneCount
            let laneCycle = index / laneCount
            let hash = FirePostBoostLayerAnimator.stableHash(text: chip.signature, index: index)
            let jitterLimit = laneCount > 1 ? min(laneStep * 0.18, 4) : 0
            let jitter = jitterLimit > 0
                ? (CGFloat(Int(hash % 100)) / 99 - 0.5) * jitterLimit
                : 0
            let y = min(
                max(CGFloat(lane) * laneStep + jitter, 0),
                max(bounds.height - Self.chipHeight, 0)
            )
            let startOffset = CGFloat(hash % 42)
            let startX = bounds.width
                + startOffset
                + CGFloat(laneCycle) * (bounds.width * 0.22 + 56)
            chip.frame = CGRect(
                x: shouldAnimate ? startX : staticX(for: index, width: chipWidth),
                y: y,
                width: chipWidth,
                height: Self.chipHeight
            )
            chip.alpha = 0.92

            guard shouldAnimate else { continue }
            let travel = startX + chipWidth + 24
            let durationJitter = Double((hash >> 8) % 90) / 100
            let delayJitter = Double((hash >> 16) % 45) / 100
            UIView.animate(
                withDuration: 9.4 + durationJitter + Double(laneCycle) * 0.35,
                delay: Double(index) * 0.48 + delayJitter,
                options: [.curveLinear, .allowUserInteraction],
                animations: {
                    chip.transform = CGAffineTransform(translationX: -travel, y: 0)
                    chip.alpha = 0.62
                },
                completion: { [weak self] finished in
                    self?.recordAnimationCompletion(runID: runID, finished: finished)
                }
            )
        }
    }

    private func staticX(for index: Int, width: CGFloat) -> CGFloat {
        let slotCount = max(chips.count + 1, 2)
        let progress = CGFloat(index + 1) / CGFloat(slotCount)
        return max((bounds.width - width) * progress, 0)
    }

    private func restartLayoutAndAnimations() {
        lastAnimatedBounds = .null
        FirePostBoostLayerAnimator.resetTiming(chips.map(\.layer))
        animationRunID &+= 1
        pendingAnimationCompletionCount = 0
        chips.forEach { chip in
            chip.layer.removeAllAnimations()
            chip.transform = .identity
        }
        setNeedsLayout()
    }

    private func removeAllLabels() {
        animationRunID &+= 1
        pendingAnimationCompletionCount = 0
        chips.forEach { chip in
            chip.layer.removeAllAnimations()
            chip.removeFromSuperview()
        }
        chips.removeAll()
        lastAnimatedBounds = .null
    }

    private func recordAnimationCompletion(runID: UInt64, finished: Bool) {
        guard finished,
              runID == animationRunID,
              pendingAnimationCompletionCount > 0 else {
            return
        }
        pendingAnimationCompletionCount -= 1
        guard pendingAnimationCompletionCount == 0,
              !batchSignature.isEmpty else {
            return
        }
        removeAllLabels()
        signature = ""
        isHidden = true
    }
}

final class FirePostBoostChipView: UIView {
    private(set) var signature: String = ""
    private let avatarContainer = UIView()
    private let avatarImageView = UIImageView()
    private let monogramLabel = UILabel()
    private let textView = FireRichTextUIView()
    private let leadingInset = FirePostCellLayoutCalculator.boostChipLeadingInset
    private let trailingInset = FirePostCellLayoutCalculator.boostChipTrailingInset
    private let avatarTextSpacing = FirePostCellLayoutCalculator.boostChipAvatarTextSpacing
    private let avatarSize = FirePostCellLayoutCalculator.boostChipAvatarSize
    private var avatarLoadTask: Task<Void, Never>?
    private var avatarLoadGeneration: UInt64 = 0

    static func styleForManual() -> FirePostBoostChipView {
        FirePostBoostChipView(
            backgroundColor: FireTheme.uiAccent.withAlphaComponent(0.10),
            borderColor: FireTheme.uiAccent.withAlphaComponent(0.18)
        )
    }

    static func styleForBarrage() -> FirePostBoostChipView {
        FirePostBoostChipView(
            backgroundColor: FireTheme.uiSurface.withAlphaComponent(0.92),
            borderColor: FireTheme.uiAccent.withAlphaComponent(0.22)
        )
    }

    init(backgroundColor: UIColor, borderColor: UIColor? = nil) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        self.backgroundColor = backgroundColor
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        if let borderColor {
            layer.borderWidth = 1.0 / UIScreen.main.scale
            layer.borderColor = borderColor.cgColor
        }

        avatarContainer.clipsToBounds = true
        avatarContainer.backgroundColor = FireTheme.uiAccent

        monogramLabel.font = UIFont.systemFont(ofSize: 9, weight: .bold)
        monogramLabel.textColor = .white
        monogramLabel.textAlignment = .center

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.isHidden = true

        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.textContainer.maximumNumberOfLines = 1
        textView.textContainer.lineBreakMode = .byTruncatingTail

        addSubview(avatarContainer)
        avatarContainer.addSubview(monogramLabel)
        avatarContainer.addSubview(avatarImageView)
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        boost: TopicPostBoostState,
        attributedText: NSAttributedString,
        signature: String,
        baseURLString: String
    ) {
        self.signature = signature
        textView.renderedContentID = "boost:\(signature)"
        textView.attributedText = attributedText
        configureAvatar(for: boost, baseURLString: baseURLString)
        setNeedsLayout()
    }

    private func configureAvatar(for boost: TopicPostBoostState, baseURLString: String) {
        avatarLoadTask?.cancel()
        avatarLoadTask = nil
        avatarLoadGeneration &+= 1
        let generation = avatarLoadGeneration

        let username = boost.user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        monogramLabel.text = monogramForUsername(username: username.isEmpty ? "?" : username)
        avatarImageView.image = nil
        avatarImageView.isHidden = true

        guard let avatarURL = fireAvatarURL(
            avatarTemplate: boost.user.avatarTemplate,
            size: avatarSize,
            scale: UIScreen.main.scale,
            baseURLString: baseURLString
        ) else {
            return
        }

        let request = FireRemoteImageRequest(url: avatarURL)
        if let cached = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            avatarImageView.image = cached
            avatarImageView.isHidden = false
            return
        }

        avatarLoadTask = Task { [weak self] in
            do {
                let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.avatarLoadGeneration == generation else { return }
                    self.avatarImageView.image = image
                    self.avatarImageView.isHidden = false
                }
            } catch {
                return
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let avatarY = max((bounds.height - avatarSize) / 2, 0)
        avatarContainer.frame = CGRect(
            x: leadingInset,
            y: avatarY,
            width: avatarSize,
            height: avatarSize
        )
        avatarContainer.layer.cornerRadius = avatarSize / 2
        monogramLabel.frame = avatarContainer.bounds
        avatarImageView.frame = avatarContainer.bounds

        let textX = avatarContainer.frame.maxX + avatarTextSpacing
        let textWidth = max(bounds.width - textX - trailingInset, 1)
        let textFrame = CGRect(x: textX, y: 0, width: textWidth, height: bounds.height)
        let measuredHeight = measuredSingleLineTextSize(maxWidth: textWidth).height
        let verticalInset = max((bounds.height - measuredHeight) / 2, 0)
        if abs(textView.textContainerInset.top - verticalInset) > 0.5
            || abs(textView.textContainerInset.bottom - verticalInset) > 0.5 {
            textView.textContainerInset = UIEdgeInsets(
                top: verticalInset,
                left: 0,
                bottom: verticalInset,
                right: 0
            )
        }
        textView.frame = textFrame
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let textMaxWidth = max(size.width - leadingInset - trailingInset - avatarSize - avatarTextSpacing, 1)
        let textSize = FirePostBoostManualLayout.measuredSingleLineTextSize(
            attributedText: textView.attributedText,
            maxWidth: textMaxWidth
        )
        let width = min(
            textSize.width + leadingInset + trailingInset + avatarSize + avatarTextSpacing,
            size.width
        )
        return CGSize(width: max(width, avatarSize + leadingInset + trailingInset), height: size.height)
    }

    private func measuredSingleLineTextSize(maxWidth: CGFloat) -> CGSize {
        FirePostBoostManualLayout.measuredSingleLineTextSize(
            attributedText: textView.attributedText,
            maxWidth: maxWidth
        )
    }
}
