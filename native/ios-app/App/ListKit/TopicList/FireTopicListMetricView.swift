import UIKit

final class FireTopicListMetricView: UIView {
    private let kind: FireTopicListMetricKind
    private let imageView = UIImageView()
    private let accessoryView = UIImageView()
    private let valueLabel = UILabel()
    private var isPulsing = false
    private var heartBalloonWorkItems: [DispatchWorkItem] = []
    private var activeHeartViews: [UIView] = []

    private static let pulseKey = "fire.metric.surgePulse"
    /// Finite breaths so surge does not loop forever on a parked row.
    private static let surgePulseRepeatCount: Float = 3
    /// Keep balloon bursts rare: only true high-likes, 2 tiny hearts, one shot.
    private static let heartBalloonCount = 2

    init(kind: FireTopicListMetricKind) {
        self.kind = kind
        super.init(frame: .zero)
        // Hearts float slightly above the chip; ancestors must not clip either.
        clipsToBounds = false
        isUserInteractionEnabled = false
        configureSubviews()
        apply(value: 0, emphasis: .normal, surgeAccessorySymbol: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        stopPulse()
        cancelHeartBalloons()
        accessoryView.isHidden = true
        accessoryView.image = nil
        apply(value: 0, emphasis: .normal, surgeAccessorySymbol: nil)
    }

    /// Updates static metric chrome. Micro-animations are opt-in via
    /// `playSurgePulse()` / `playHeartBalloons(tint:)` after the list settles.
    func configure(
        value: UInt32,
        emphasis: FireTopicListMetricEmphasis,
        surgeAccessorySymbol: String? = nil,
        animateEffects: Bool = true
    ) {
        apply(value: value, emphasis: emphasis, surgeAccessorySymbol: surgeAccessorySymbol)

        // Legacy path (if any caller still wants immediate play). Prefer the
        // coordinator-driven APIs from the topic cell.
        guard animateEffects else { return }
        if emphasis == .surge {
            playSurgePulse()
        }
        if kind == .likes, emphasis == .high {
            playHeartBalloons(tint: Self.tint(kind: kind, emphasis: emphasis))
        }
    }

    static func tint(kind: FireTopicListMetricKind, emphasis: FireTopicListMetricEmphasis) -> UIColor {
        style(kind: kind, emphasis: emphasis).tint
    }

    func playSurgePulse() {
        guard kind == .views else { return }
        guard !accessoryView.isHidden else { return }
        startPulseIfNeeded()
    }

    func playHeartBalloons(tint: UIColor) {
        guard kind == .likes else { return }
        scheduleHeartBalloons(tint: tint)
    }

    private func apply(
        value: UInt32,
        emphasis: FireTopicListMetricEmphasis,
        surgeAccessorySymbol: String?
    ) {
        // Always clear running effects before restyling — scrolling may rebind the cell.
        stopPulse()
        cancelHeartBalloons()

        let style = Self.style(kind: kind, emphasis: emphasis)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: style.symbolWeight)
        imageView.image = UIImage(systemName: style.symbol, withConfiguration: symbolConfig)
        imageView.tintColor = style.tint

        valueLabel.text = FireTopicPresentation.compactCount(value)
        valueLabel.textColor = style.tint
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: style.fontWeight)

        if emphasis == .surge, let accessory = surgeAccessorySymbol {
            let accessoryConfig = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            accessoryView.image = UIImage(systemName: accessory, withConfiguration: accessoryConfig)
            accessoryView.tintColor = style.accessoryTint
            accessoryView.isHidden = false
        } else {
            accessoryView.isHidden = true
            accessoryView.image = nil
        }

        accessibilityLabel = Self.accessibilityLabel(
            kind: kind,
            value: value,
            emphasis: emphasis
        )
    }

    private func configureSubviews() {
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        accessoryView.contentMode = .scaleAspectFit
        accessoryView.setContentHuggingPriority(.required, for: .horizontal)
        accessoryView.isHidden = true

        valueLabel.numberOfLines = 1
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Keep icon→number spacing constant. Surge badge sits after the count so
        // flame/rocket never opens a gap between the metric glyph and digits.
        let stack = UIStackView(arrangedSubviews: [imageView, valueLabel, accessoryView])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 3
        stack.clipsToBounds = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Tighter gap between the count and the surge badge than icon→count.
        stack.setCustomSpacing(2, after: valueLabel)

        addSubview(stack)
        let imageWidth = imageView.widthAnchor.constraint(equalToConstant: 13)
        let imageHeight = imageView.heightAnchor.constraint(equalToConstant: 13)
        let accessoryWidth = accessoryView.widthAnchor.constraint(equalToConstant: 10)
        let accessoryHeight = accessoryView.heightAnchor.constraint(equalToConstant: 10)
        // Soften fixed icon sizes so parent self-sizing passes never break required constraints.
        [imageWidth, imageHeight, accessoryWidth, accessoryHeight].forEach {
            $0.priority = UILayoutPriority(999)
        }
        NSLayoutConstraint.activate([
            imageWidth,
            imageHeight,
            accessoryWidth,
            accessoryHeight,
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func startPulseIfNeeded() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            stopPulse()
            return
        }
        guard !isPulsing else { return }
        isPulsing = true

        // Tiny breathe on the surge badge only — finite, never the whole metric row.
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.55
        opacity.toValue = 1.0
        opacity.duration = 1.6
        opacity.autoreverses = true
        opacity.repeatCount = Self.surgePulseRepeatCount
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        opacity.isRemovedOnCompletion = false
        opacity.fillMode = .forwards

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.08
        scale.duration = 1.6
        scale.autoreverses = true
        scale.repeatCount = Self.surgePulseRepeatCount
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scale.isRemovedOnCompletion = false
        scale.fillMode = .forwards

        accessoryView.layer.add(opacity, forKey: Self.pulseKey + ".opacity")
        accessoryView.layer.add(scale, forKey: Self.pulseKey + ".scale")

        let total = TimeInterval(Self.surgePulseRepeatCount) * 1.6 * 2
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            self?.stopPulse()
        }
    }

    private func stopPulse() {
        isPulsing = false
        accessoryView.layer.removeAnimation(forKey: Self.pulseKey + ".opacity")
        accessoryView.layer.removeAnimation(forKey: Self.pulseKey + ".scale")
        accessoryView.layer.opacity = 1
        accessoryView.layer.transform = CATransform3DIdentity
    }

    private func scheduleHeartBalloons(tint: UIColor) {
        guard kind == .likes else { return }
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        cancelHeartBalloons()

        // Defer until after Auto Layout so the heart originates on the icon.
        let start = DispatchWorkItem { [weak self] in
            self?.emitHeartBalloons(tint: tint)
        }
        heartBalloonWorkItems.append(start)
        DispatchQueue.main.async(execute: start)
    }

    private func emitHeartBalloons(tint: UIColor) {
        // Stagger two micro hearts so it reads as a soft bubble, not a particle storm.
        for index in 0..<Self.heartBalloonCount {
            let work = DispatchWorkItem { [weak self] in
                self?.spawnHeartBalloon(index: index, tint: tint)
            }
            heartBalloonWorkItems.append(work)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.08 + Double(index) * 0.28,
                execute: work
            )
        }
    }

    private func spawnHeartBalloon(index: Int, tint: UIColor) {
        guard window != nil, bounds.width > 0 else { return }

        let size: CGFloat = index == 0 ? 8 : 7
        let config = UIImage.SymbolConfiguration(pointSize: size - 1, weight: .bold)
        let heart = UIImageView(image: UIImage(systemName: "heart.fill", withConfiguration: config))
        heart.tintColor = tint.withAlphaComponent(0.82)
        heart.contentMode = .scaleAspectFit
        heart.isUserInteractionEnabled = false
        heart.alpha = 0

        let iconFrame = imageView.convert(imageView.bounds, to: self)
        // Slight horizontal scatter so the two hearts do not stack.
        let driftX: CGFloat = index == 0 ? -3 : 5
        heart.frame = CGRect(
            x: iconFrame.midX - size / 2 + driftX * 0.2,
            y: iconFrame.midY - size / 2,
            width: size,
            height: size
        )
        addSubview(heart)
        activeHeartViews.append(heart)

        let rise: CGFloat = -(16 + CGFloat(index) * 5)
        let endDriftX: CGFloat = driftX

        // Phase 1: soft pop + lift. Phase 2: fade while still drifting up.
        UIView.animate(
            withDuration: 0.55,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            heart.alpha = 0.88
            heart.transform = CGAffineTransform(translationX: endDriftX * 0.45, y: rise * 0.55)
                .scaledBy(x: 1.08, y: 1.08)
        } completion: { [weak self, weak heart] _ in
            guard let heart else { return }
            UIView.animate(
                withDuration: 0.75,
                delay: 0.02,
                options: [.curveEaseIn, .allowUserInteraction, .beginFromCurrentState]
            ) {
                heart.alpha = 0
                heart.transform = CGAffineTransform(translationX: endDriftX, y: rise)
                    .scaledBy(x: 0.72, y: 0.72)
            } completion: { [weak self, weak heart] _ in
                heart?.removeFromSuperview()
                if let heart {
                    self?.activeHeartViews.removeAll { $0 === heart }
                }
            }
        }
    }

    private func cancelHeartBalloons() {
        heartBalloonWorkItems.forEach { $0.cancel() }
        heartBalloonWorkItems.removeAll()
        activeHeartViews.forEach { heart in
            heart.layer.removeAllAnimations()
            heart.removeFromSuperview()
        }
        activeHeartViews.removeAll()
    }

    private struct Style {
        let symbol: String
        let symbolWeight: UIImage.SymbolWeight
        let tint: UIColor
        let fontWeight: UIFont.Weight
        let accessoryTint: UIColor
    }

    private static func style(
        kind: FireTopicListMetricKind,
        emphasis: FireTopicListMetricEmphasis
    ) -> Style {
        let muted = FireTheme.uiTertiaryInk
        let soft = FireTheme.uiSubtleInk

        switch (kind, emphasis) {
        case (.replies, .normal):
            return Style(
                symbol: "bubble.left",
                symbolWeight: .regular,
                tint: muted,
                fontWeight: .regular,
                accessoryTint: muted
            )
        case (.replies, .notable):
            return Style(
                symbol: "bubble.left.fill",
                symbolWeight: .medium,
                tint: soft,
                fontWeight: .medium,
                accessoryTint: soft
            )
        case (.replies, .high), (.replies, .surge):
            return Style(
                symbol: "bubble.left.fill",
                symbolWeight: .semibold,
                tint: FireTheme.uiInfo,
                fontWeight: .semibold,
                accessoryTint: FireTheme.uiInfo
            )

        case (.views, .normal):
            return Style(
                symbol: "chart.bar",
                symbolWeight: .regular,
                tint: muted,
                fontWeight: .regular,
                accessoryTint: muted
            )
        case (.views, .notable):
            return Style(
                symbol: "chart.bar.fill",
                symbolWeight: .medium,
                tint: soft,
                fontWeight: .medium,
                accessoryTint: soft
            )
        case (.views, .high):
            return Style(
                symbol: "chart.bar.fill",
                symbolWeight: .semibold,
                tint: UIColor.systemTeal,
                fontWeight: .semibold,
                accessoryTint: UIColor.systemTeal
            )
        case (.views, .surge):
            return Style(
                symbol: "chart.bar.fill",
                symbolWeight: .semibold,
                tint: FireTheme.uiWarning,
                fontWeight: .semibold,
                accessoryTint: FireTheme.uiAccent
            )

        case (.likes, .normal):
            return Style(
                symbol: "heart",
                symbolWeight: .regular,
                tint: muted,
                fontWeight: .regular,
                accessoryTint: muted
            )
        case (.likes, .notable):
            return Style(
                symbol: "heart.fill",
                symbolWeight: .medium,
                tint: UIColor.systemPink.withAlphaComponent(0.85),
                fontWeight: .medium,
                accessoryTint: UIColor.systemPink
            )
        case (.likes, .high), (.likes, .surge):
            return Style(
                symbol: "heart.fill",
                symbolWeight: .semibold,
                tint: FireTheme.uiAccent,
                fontWeight: .semibold,
                accessoryTint: FireTheme.uiAccent
            )
        }
    }

    private static func accessibilityLabel(
        kind: FireTopicListMetricKind,
        value: UInt32,
        emphasis: FireTopicListMetricEmphasis
    ) -> String {
        let base: String
        switch kind {
        case .replies: base = "\(value) 回复"
        case .views: base = "\(value) 浏览"
        case .likes: base = "\(value) 赞"
        }
        switch emphasis {
        case .normal:
            return base
        case .notable:
            return base + "，热度偏高"
        case .high:
            return base + "，热门"
        case .surge:
            return base + "，浏览激增"
        }
    }
}
