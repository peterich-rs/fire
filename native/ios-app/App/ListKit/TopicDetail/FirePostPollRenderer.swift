import UIKit

struct FirePostPollOptionRenderModel: Hashable, Sendable {
    let id: String
    let title: String
    let votes: UInt32
    let isSelected: Bool
}

struct FirePostPollRenderModel: Hashable, Sendable {
    let id: UInt64
    let name: String
    let title: String
    let kind: String
    let status: String
    let voters: UInt32
    let userVotes: [String]
    let options: [FirePostPollOptionRenderModel]

    var allowsMultipleSelection: Bool {
        kind.localizedCaseInsensitiveContains("multiple")
    }

    var isClosed: Bool {
        status.localizedCaseInsensitiveContains("closed")
    }

    var signature: String {
        let optionSignature = options.map { option in
            [
                option.id,
                option.title,
                String(option.votes),
                String(option.isSelected),
            ].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")
        return [
            String(id),
            name,
            title,
            kind,
            status,
            String(voters),
            userVotes.joined(separator: ","),
            optionSignature,
        ].joined(separator: "\u{1D}")
    }

    static func models(from polls: [PollState]) -> [FirePostPollRenderModel] {
        polls.map { poll in
            let selected = Set(poll.userVotes)
            let title = trimmedNonEmpty(poll.name) ?? "投票"
            return FirePostPollRenderModel(
                id: poll.id,
                name: poll.name,
                title: title,
                kind: poll.kind,
                status: poll.status,
                voters: poll.voters,
                userVotes: poll.userVotes,
                options: poll.options.map { option in
                    FirePostPollOptionRenderModel(
                        id: option.id,
                        title: optionTitle(fromHTML: option.html, fallback: option.id),
                        votes: option.votes,
                        isSelected: selected.contains(option.id)
                    )
                }
            )
        }
    }

    private static func trimmedNonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionTitle(fromHTML html: String, fallback: String) -> String {
        let cacheKey = html as NSString
        if let cached = FirePostPollPlainTextCache.cache.object(forKey: cacheKey) {
            return cached as String
        }

        let parsed = FireRichTextParser.parse(html: html, baseURLString: "")
            .plainText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parsed.isEmpty ? fallback : parsed
        FirePostPollPlainTextCache.cache.setObject(title as NSString, forKey: cacheKey)
        return title
    }
}

private enum FirePostPollPlainTextCache {
    static let cache = NSCache<NSString, NSString>()
}

final class FirePostPollView: UIView {
    private static let contentInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    private static let headerSpacing: CGFloat = 10
    private static let optionSpacing: CGFloat = 8
    private static let footerSpacing: CGFloat = 10
    private static let footerHeight: CGFloat = 30
    fileprivate static let minOptionHeight: CGFloat = 40
    fileprivate static let accentColor = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.96, green: 0.45, blue: 0.22, alpha: 1)
        }
        return UIColor(red: 0.91, green: 0.39, blue: 0.18, alpha: 1)
    }

    private let titleLabel = UILabel()
    private let votersLabel = UILabel()
    private let removeVoteButton = UIButton(type: .system)
    private let submitButton = UIButton(type: .system)
    private var optionButtons: [FirePostPollOptionButton] = []
    private var model: FirePostPollRenderModel?
    private var modelSignature: String?
    private var selectedOptionIDs = Set<String>()
    private var canInteract = false
    private var isMutating = false
    private var onSubmit: (([String]) -> Void)?
    private var onRemoveVote: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func preferredHeight(
        for model: FirePostPollRenderModel,
        availableWidth: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        let width = max(availableWidth, 1)
        let contentWidth = max(width - contentInsets.left - contentInsets.right, 1)
        let titleFont = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold),
            compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        )
        let captionFont = UIFont.preferredFont(
            forTextStyle: .caption1,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        )
        let votersWidth = ceil((String(model.voters) as NSString).size(withAttributes: [.font: captionFont]).width) + 44
        let titleWidth = max(contentWidth - votersWidth - 8, 1)
        let headerHeight = max(
            textHeight(model.title, width: titleWidth, font: titleFont),
            ceil(captionFont.lineHeight)
        )
        let optionsHeight = model.options.enumerated().reduce(CGFloat.zero) { partialResult, item in
            let spacing = item.offset == 0 ? CGFloat.zero : optionSpacing
            return partialResult + spacing + FirePostPollOptionButton.preferredHeight(
                for: item.element,
                availableWidth: contentWidth,
                contentSizeCategory: contentSizeCategory
            )
        }
        return ceil(contentInsets.top
            + headerHeight
            + headerSpacing
            + optionsHeight
            + footerSpacing
            + footerHeight
            + contentInsets.bottom)
    }

    func configure(
        model: FirePostPollRenderModel,
        canInteract: Bool,
        isMutating: Bool,
        onSubmit: @escaping ([String]) -> Void,
        onRemoveVote: @escaping () -> Void
    ) {
        self.model = model
        self.canInteract = canInteract
        self.isMutating = isMutating
        self.onSubmit = onSubmit
        self.onRemoveVote = onRemoveVote

        if modelSignature != model.signature {
            modelSignature = model.signature
            selectedOptionIDs = Set(model.userVotes)
            rebuildOptions(model: model)
        }

        titleLabel.text = model.title
        votersLabel.text = "\(model.voters) 人参与"
        updateSelectionAppearance()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let model else { return }

        let bounds = bounds.inset(by: Self.contentInsets)
        let votersSize = votersLabel.sizeThatFits(CGSize(width: bounds.width * 0.4, height: .greatestFiniteMagnitude))
        votersLabel.frame = CGRect(
            x: bounds.maxX - votersSize.width,
            y: bounds.minY,
            width: votersSize.width,
            height: ceil(votersSize.height)
        )
        titleLabel.frame = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(votersLabel.frame.minX - bounds.minX - 8, 1),
            height: max(votersLabel.frame.height, titleLabel.sizeThatFits(CGSize(width: max(votersLabel.frame.minX - bounds.minX - 8, 1), height: .greatestFiniteMagnitude)).height)
        )

        var cursorY = max(titleLabel.frame.maxY, votersLabel.frame.maxY) + Self.headerSpacing
        for (index, button) in optionButtons.enumerated() {
            if index > 0 {
                cursorY += Self.optionSpacing
            }
            let height = FirePostPollOptionButton.preferredHeight(
                for: model.options[index],
                availableWidth: bounds.width,
                contentSizeCategory: traitCollection.preferredContentSizeCategory
            )
            button.frame = CGRect(x: bounds.minX, y: cursorY, width: bounds.width, height: height)
            cursorY += height
        }

        cursorY += Self.footerSpacing
        let submitWidth: CGFloat = 72
        submitButton.frame = CGRect(x: bounds.maxX - submitWidth, y: cursorY, width: submitWidth, height: Self.footerHeight)
        removeVoteButton.frame = CGRect(
            x: bounds.minX,
            y: cursorY,
            width: max(submitButton.frame.minX - bounds.minX - 12, 1),
            height: Self.footerHeight
        )
    }

    private func setup() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.masksToBounds = true

        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        votersLabel.adjustsFontForContentSizeCategory = true
        votersLabel.numberOfLines = 1
        votersLabel.textAlignment = .right
        removeVoteButton.contentHorizontalAlignment = .leading
        removeVoteButton.setTitle("撤销投票", for: .normal)
        removeVoteButton.setImage(UIImage(systemName: "arrow.uturn.left"), for: .normal)
        removeVoteButton.addTarget(self, action: #selector(removeVoteTapped), for: .touchUpInside)
        submitButton.setTitle("提交", for: .normal)
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        addSubview(titleLabel)
        addSubview(votersLabel)
        addSubview(removeVoteButton)
        addSubview(submitButton)
        applyTypography()
        applyColors()
    }

    private func applyTypography() {
        let subheadlinePointSize = UIFont.preferredFont(forTextStyle: .subheadline).pointSize
        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(ofSize: subheadlinePointSize, weight: .semibold)
        )
        votersLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        removeVoteButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
        submitButton.titleLabel?.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .semibold)
        )
        optionButtons.forEach { $0.applyTypography() }
    }

    private func applyColors() {
        titleLabel.textColor = .label
        votersLabel.textColor = .tertiaryLabel
        removeVoteButton.tintColor = .secondaryLabel
        submitButton.tintColor = .white
        submitButton.backgroundColor = Self.accentColor
        submitButton.layer.cornerRadius = Self.footerHeight / 2
        submitButton.layer.masksToBounds = true
        optionButtons.forEach { $0.applyColors(accentColor: Self.accentColor) }
    }

    private func rebuildOptions(model: FirePostPollRenderModel) {
        optionButtons.forEach { $0.removeFromSuperview() }
        optionButtons = model.options.map { option in
            let button = FirePostPollOptionButton()
            button.configure(option: option)
            button.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            addSubview(button)
            return button
        }
        applyTypography()
        applyColors()
    }

    private func updateSelectionAppearance() {
        guard let model else { return }
        let canSelect = canInteract && !isMutating && !model.isClosed
        for button in optionButtons {
            button.isEnabled = canSelect
            button.isOptionSelected = selectedOptionIDs.contains(button.optionID)
        }

        let userVotes = Set(model.userVotes)
        let canSubmit = canSelect && !selectedOptionIDs.isEmpty && selectedOptionIDs != userVotes
        submitButton.isHidden = !canSubmit
        submitButton.isEnabled = canSubmit
        removeVoteButton.isHidden = model.userVotes.isEmpty
        removeVoteButton.isEnabled = canSelect && !model.userVotes.isEmpty
    }

    @objc
    private func optionTapped(_ sender: FirePostPollOptionButton) {
        guard let model,
              canInteract,
              !isMutating,
              !model.isClosed else {
            return
        }

        if model.allowsMultipleSelection {
            if selectedOptionIDs.contains(sender.optionID) {
                selectedOptionIDs.remove(sender.optionID)
            } else {
                selectedOptionIDs.insert(sender.optionID)
            }
        } else {
            if selectedOptionIDs.contains(sender.optionID) {
                selectedOptionIDs.removeAll()
            } else {
                selectedOptionIDs = [sender.optionID]
            }
        }
        updateSelectionAppearance()
    }

    @objc
    private func submitTapped() {
        guard let model,
              canInteract,
              !isMutating,
              !model.isClosed,
              !selectedOptionIDs.isEmpty else {
            return
        }
        onSubmit?(selectedOptionIDs.sorted())
    }

    @objc
    private func removeVoteTapped() {
        guard canInteract, !isMutating else { return }
        onRemoveVote?()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            applyTypography()
            setNeedsLayout()
        }
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            applyColors()
        }
    }

    fileprivate static func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }
}

private final class FirePostPollOptionButton: UIControl {
    private let checkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let votesLabel = UILabel()
    private(set) var optionID = ""
    var isOptionSelected = false {
        didSet { applySelectedState() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func preferredHeight(
        for option: FirePostPollOptionRenderModel,
        availableWidth: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        let font = UIFont.preferredFont(
            forTextStyle: .subheadline,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        )
        let titleWidth = max(availableWidth - 22 - 10 - 52 - 24, 1)
        let titleHeight = FirePostPollView.textHeight(option.title, width: titleWidth, font: font)
        return max(FirePostPollView.minOptionHeight, ceil(titleHeight + 20))
    }

    func configure(option: FirePostPollOptionRenderModel) {
        optionID = option.id
        titleLabel.text = option.title
        votesLabel.text = "\(option.votes)"
        isOptionSelected = option.isSelected
        accessibilityLabel = "\(option.title)，\(option.votes) 票"
        accessibilityTraits = isOptionSelected ? [.button, .selected] : [.button]
        setNeedsLayout()
    }

    func applyTypography() {
        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        votesLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: UIFont.monospacedDigitSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                weight: .regular
            )
        )
    }

    func applyColors(accentColor: UIColor) {
        checkImageView.tintColor = isOptionSelected ? accentColor : .tertiaryLabel
        titleLabel.textColor = .label
        votesLabel.textColor = .tertiaryLabel
        backgroundColor = isOptionSelected
            ? accentColor.withAlphaComponent(0.10)
            : .tertiarySystemFill
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insetBounds = bounds.insetBy(dx: 12, dy: 8)
        checkImageView.frame = CGRect(
            x: insetBounds.minX,
            y: insetBounds.midY - 10,
            width: 20,
            height: 20
        )
        let votesWidth = min(max(votesLabel.sizeThatFits(insetBounds.size).width, 28), 52)
        votesLabel.frame = CGRect(
            x: insetBounds.maxX - votesWidth,
            y: insetBounds.minY,
            width: votesWidth,
            height: insetBounds.height
        )
        titleLabel.frame = CGRect(
            x: checkImageView.frame.maxX + 10,
            y: insetBounds.minY,
            width: max(votesLabel.frame.minX - checkImageView.frame.maxX - 18, 1),
            height: insetBounds.height
        )
    }

    private func setup() {
        layer.cornerRadius = 8
        layer.masksToBounds = true
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        votesLabel.adjustsFontForContentSizeCategory = true
        votesLabel.textAlignment = .right
        isAccessibilityElement = true
        addSubview(checkImageView)
        addSubview(titleLabel)
        addSubview(votesLabel)
        applyTypography()
        applySelectedState()
    }

    private func applySelectedState() {
        checkImageView.image = UIImage(systemName: isOptionSelected ? "checkmark.circle.fill" : "circle")
        accessibilityTraits = isOptionSelected ? [.button, .selected] : [.button]
        applyColors(accentColor: FirePostPollView.accentColor)
    }
}
