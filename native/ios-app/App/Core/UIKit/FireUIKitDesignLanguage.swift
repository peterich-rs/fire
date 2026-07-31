import SnapKit
import SwiftUI
import UIKit

// MARK: - Hosted SwiftUI pages

@MainActor
enum FireHosting {
    /// Product-facing `UIHostingController` with Fire canvas background so system white
    /// does not flash under SwiftUI content or at safe-area edges.
    static func controller<Content: View>(
        rootView: Content,
        title: String? = nil
    ) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = FireTheme.uiCanvas
        host.navigationItem.largeTitleDisplayMode = .never
        if let title {
            host.title = title
            host.navigationItem.title = title
        }
        return host
    }
}

// MARK: - Card styling

extension UIView {
    /// Floating card used across settings / profile (tight continuous corners).
    func fireApplyCardStyle(
        cornerRadius: CGFloat = FireTheme.cornerRadius,
        fill: UIColor = FireTheme.uiSurface
    ) {
        backgroundColor = fill
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    func fireApplyIconWellStyle(
        cornerRadius: CGFloat = FireTheme.iconWellCornerRadius
    ) {
        backgroundColor = FireTheme.uiIconWell
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }
}

// MARK: - Section header

final class FireUIKitSectionHeaderLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 12, weight: .semibold)
        textColor = FireTheme.uiTertiaryInk
        numberOfLines = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSectionTitle(_ title: String) {
        // Reference uses Latin uppercase; Chinese keeps original case.
        let isLatin = title.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.whitespaces.contains($0) || $0 == "&" || $0 == "-"
        }
        text = isLatin ? title.uppercased() : title
    }
}

// MARK: - Settings / profile row

final class FireUIKitListRowView: UIControl {
    struct Content: Equatable {
        var systemImage: String
        var title: String
        var subtitle: String? = nil
        var value: String? = nil
        var showsChevron: Bool = true
        /// Symbol color inside the well. Defaults to white when a well color is provided.
        var iconTint: UIColor? = nil
        /// Colored rounded square behind the symbol (reference-style accent well).
        var iconWellColor: UIColor? = nil
    }

    private let iconWell = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let valueLabel = UILabel()
    private let chevronView = UIImageView()
    private let textStack = UIStackView()
    private let rowStack = UIStackView()
    private let highlightView = UIView()

    override var isHighlighted: Bool {
        didSet {
            highlightView.alpha = isHighlighted ? 1 : 0
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ content: Content) {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = UIImage(systemName: content.systemImage, withConfiguration: config)

        if let wellColor = content.iconWellColor {
            iconWell.backgroundColor = wellColor
            iconView.tintColor = content.iconTint ?? .white
        } else {
            iconWell.backgroundColor = FireTheme.uiIconWell
            iconView.tintColor = content.iconTint ?? FireTheme.uiInk
        }

        titleLabel.text = content.title

        let subtitle = content.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty

        let value = content.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        valueLabel.text = value
        valueLabel.isHidden = value.isEmpty

        chevronView.isHidden = !content.showsChevron
        accessibilityLabel = [content.title, content.subtitle, content.value]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "，")
    }

    private func configureHierarchy() {
        clipsToBounds = true

        highlightView.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        addSubview(highlightView)
        highlightView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconWell.fireApplyIconWellStyle()
        iconView.contentMode = .scaleAspectFit
        iconWell.addSubview(iconView)
        iconWell.snp.makeConstraints { make in
            make.width.height.equalTo(FireTheme.iconWellSize)
        }
        iconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(15)
        }

        titleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = FireTheme.uiInk
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = FireTheme.uiSubtleInk
        subtitleLabel.numberOfLines = 2

        valueLabel.font = .systemFont(ofSize: 16, weight: .regular)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = FireTheme.uiTertiaryInk
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevronView.image = UIImage(systemName: "chevron.right", withConfiguration: chevronConfig)
        chevronView.tintColor = FireTheme.uiTertiaryInk
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 14
        rowStack.isUserInteractionEnabled = false
        rowStack.addArrangedSubview(iconWell)
        rowStack.addArrangedSubview(textStack)
        rowStack.addArrangedSubview(valueLabel)
        rowStack.addArrangedSubview(chevronView)

        addSubview(rowStack)
        rowStack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.trailing.equalToSuperview().offset(-14)
            make.top.equalToSuperview().offset(14)
            make.bottom.equalToSuperview().offset(-14)
        }

        isAccessibilityElement = true
        accessibilityTraits = .button
    }
}

// MARK: - Grouped card of rows (with hairline separators)

final class FireUIKitSettingsCardView: UIView {
    private let stack = UIStackView()
    private var rowViews: [FireUIKitListRowView] = []
    private var actions: [(() -> Void)?] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        fireApplyCardStyle()
        stack.axis = .vertical
        stack.spacing = 0
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRows(_ items: [(FireUIKitListRowView.Content, (() -> Void)?)]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rowViews.removeAll()
        actions = items.map(\.1)

        for (index, item) in items.enumerated() {
            if index > 0 {
                let separatorHost = UIView()
                separatorHost.backgroundColor = .clear
                let line = UIView()
                line.backgroundColor = FireTheme.uiDivider
                separatorHost.addSubview(line)
                line.snp.makeConstraints { make in
                    // Inset past icon well (leading + well + gap).
                    make.leading.equalToSuperview().offset(14 + FireTheme.iconWellSize + 14)
                    make.trailing.equalToSuperview()
                    make.top.bottom.equalToSuperview()
                    make.height.equalTo(1.0 / UIScreen.main.scale)
                }
                stack.addArrangedSubview(separatorHost)
            }

            let row = FireUIKitListRowView()
            row.apply(item.0)
            row.tag = index
            row.addTarget(self, action: #selector(handleRowTap(_:)), for: .touchUpInside)
            row.fireBindPressBounce(.compact)
            row.isEnabled = item.1 != nil
            if item.1 == nil {
                row.accessibilityTraits = .staticText
            }
            stack.addArrangedSubview(row)
            rowViews.append(row)
        }
    }

    @objc
    private func handleRowTap(_ sender: FireUIKitListRowView) {
        let index = sender.tag
        guard actions.indices.contains(index) else { return }
        FireMotionHaptics.selection()
        actions[index]?()
    }
}

// MARK: - Appearance capsule (reference: Dark | System | Light only)

/// Three-segment control matching the reference settings screenshot exactly:
/// - Outer floating card track
/// - Selected segment: raised pill + **green** icon/title
/// - Unselected: muted gray
/// - Only Dark / System / Light (no OLED in the control)
final class FireUIKitAppearanceCapsuleControl: UIView {
    static let pickerOptions: [FireAppearancePreference] = [.dark, .system, .light]

    /// Reference selected color (bright green).
    static let selectedTint = UIColor(red: 0.18, green: 0.82, blue: 0.35, alpha: 1)

    var selectedPreference: FireAppearancePreference = .system {
        didSet {
            let normalized = Self.normalizedForPicker(selectedPreference)
            if selectedPreference != normalized {
                selectedPreference = normalized
                return
            }
            updateButtonStyles()
            // Defer pill placement to layoutSubviews so user-tap animation can
            // interpolate from the previous segment. First paint still places the
            // pill once Auto Layout resolves button frames (see layoutSubviews /
            // didMoveToWindow).
            setNeedsLayout()
        }
    }

    var onChange: ((FireAppearancePreference) -> Void)?

    private let options = FireUIKitAppearanceCapsuleControl.pickerOptions
    private let stack = UIStackView()
    private var buttons: [FireAppearancePreference: UIButton] = [:]
    private let selectionPill = UIView()
    /// True after the pill has been placed on a segment with a non-zero frame.
    /// Prevents first-show animation from CGRect.zero (top-left flash).
    private var hasPositionedSelectionPill = false
    /// While true, `layoutSubviews` must not snap the pill (user-tap animation owns it).
    private var isAnimatingSelectionPill = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        fireApplyCardStyle()
        clipsToBounds = true

        selectionPill.backgroundColor = UIColor { traits in
            // Raised pill inside charcoal track (reference)
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1)
                : UIColor(white: 0.93, alpha: 1)
        }
        selectionPill.layer.cornerCurve = .continuous
        // Stay hidden until the first valid segment layout so we never flash at (0,0).
        selectionPill.isHidden = true
        addSubview(selectionPill)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.spacing = 0
        stack.isUserInteractionEnabled = true
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5))
            make.height.equalTo(42)
        }

        for preference in options {
            let button = UIButton(type: .system)
            button.configuration = makeConfiguration(for: preference, selected: false)
            button.addAction(UIAction { [weak self] _ in
                self?.handleTap(preference)
            }, for: .touchUpInside)
            button.accessibilityLabel = preference.title
            buttons[preference] = button
            stack.addArrangedSubview(button)
        }
        updateButtonStyles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `.oled` is treated as dark in this three-option control.
    static func normalizedForPicker(_ preference: FireAppearancePreference) -> FireAppearancePreference {
        switch preference {
        case .oled, .dark: return .dark
        case .system: return .system
        case .light: return .light
        }
    }

    // MARK: - Testing seams

    /// Current selection-pill frame after layout (unit tests via `@testable import Fire`).
    var selectionPillFrameForTesting: CGRect { selectionPill.frame }

    var isSelectionPillHiddenForTesting: Bool { selectionPill.isHidden }

    func buttonFrameForTesting(_ preference: FireAppearancePreference) -> CGRect? {
        let key = Self.normalizedForPicker(preference)
        guard let button = buttons[key] else { return nil }
        return button.convert(button.bounds, to: self)
    }

    private func handleTap(_ preference: FireAppearancePreference) {
        let normalized = Self.normalizedForPicker(preference)
        guard selectedPreference != normalized else { return }
        // Capture before preference mutation so layoutSubviews cannot snap the pill
        // to the new segment before the animation block runs.
        let canAnimate = hasPositionedSelectionPill && !selectionPill.isHidden
        if canAnimate {
            isAnimatingSelectionPill = true
        }
        selectedPreference = normalized
        FireMotionHaptics.selection()
        onChange?(normalized)
        // Only animate segment-to-segment moves after an initial placement exists.
        // First placement must snap — otherwise the pill flies in from top-left.
        if canAnimate {
            UIView.fireAnimate(kind: .tap) {
                self.layoutSelectionPill(animated: true)
            } completion: { [weak self] _ in
                self?.isAnimatingSelectionPill = false
                // Settle to Auto Layout geometry after the animation ends.
                self?.layoutSelectionPill(animated: false)
            }
        } else {
            layoutSelectionPill(animated: false)
        }
    }

    private func makeConfiguration(
        for preference: FireAppearancePreference,
        selected: Bool
    ) -> UIButton.Configuration {
        // UI only ever builds buttons for pickerOptions (3). `preference` is always
        // one of .dark / .system / .light after normalization.
        precondition(options.contains(preference), "Appearance picker only supports dark/system/light")

        let title: String
        let symbol: String
        switch preference {
        case .dark:
            // Reference: "Dark" + moon
            title = "深色"
            symbol = "moon"
        case .system:
            // Reference: "System" + half-circle
            title = "系统"
            symbol = "circle.lefthalf.filled"
        case .light:
            // Reference: "Light" + sun
            title = "浅色"
            symbol = "sun.max"
        case .oled:
            // Unreachable in the picker UI; kept only so the enum switch is exhaustive.
            preconditionFailure("OLED is not a picker segment; normalize to .dark first")
        }

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol)
        config.title = title
        config.imagePadding = 6
        config.imagePlacement = .leading
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        let color = selected ? Self.selectedTint : FireTheme.uiSubtleInk
        config.baseForegroundColor = color
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 15, weight: selected ? .semibold : .regular)
            return outgoing
        }
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: selected ? .semibold : .regular
        )
        return config
    }

    private func updateButtonStyles() {
        let selected = Self.normalizedForPicker(selectedPreference)
        for preference in options {
            buttons[preference]?.configuration = makeConfiguration(
                for: preference,
                selected: preference == selected
            )
        }
    }

    /// Positions the raised selection pill over the active segment.
    /// - Parameter animated: When true *and* the pill was already placed, the caller
    ///   may wrap this in an animation. First placement always snaps without motion.
    private func layoutSelectionPill(animated: Bool) {
        stack.layoutIfNeeded()
        let selected = Self.normalizedForPicker(selectedPreference)
        guard let button = buttons[selected], button.bounds.width > 1 else {
            // Invalid geometry: hide and require a snap on the next successful layout
            // so we never animate out of CGRect.zero.
            selectionPill.isHidden = true
            hasPositionedSelectionPill = false
            return
        }
        let target = button.convert(button.bounds, to: self)
        let apply = {
            self.selectionPill.frame = target
            self.selectionPill.layer.cornerRadius = target.height / 2
            self.selectionPill.isHidden = false
        }
        let shouldAnimate = animated && hasPositionedSelectionPill && !selectionPill.isHidden
        if shouldAnimate {
            apply()
        } else {
            UIView.performWithoutAnimation(apply)
        }
        hasPositionedSelectionPill = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout passes must never animate from a zero frame.
        // Skip while a segment-change animation is in flight so we do not snap
        // the pill mid-interpolation. `handleTap` owns animated placement.
        guard !isAnimatingSelectionPill else { return }
        layoutSelectionPill(animated: false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            // Detached (e.g. settings rebuildContent): next attach must snap.
            hasPositionedSelectionPill = false
            selectionPill.isHidden = true
            return
        }
        setNeedsLayout()
        layoutIfNeeded()
        layoutSelectionPill(animated: false)
    }
}
