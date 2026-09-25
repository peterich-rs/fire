import UIKit

final class FireTopicListAvatarView: UIView {
    private let imageView = UIImageView()
    private let monogramLabel = UILabel()
    private var imageTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        imageTask?.cancel()
        imageTask = nil
        generation &+= 1
        imageView.image = nil
        imageView.alpha = 0
    }

    func configure(
        username: String,
        avatarTemplate: String?,
        baseURLString: String
    ) {
        prepareForReuse()
        monogramLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        backgroundColor = FireTopicListPalette.accent
        monogramLabel.text = monogramForUsername(username: username.isEmpty ? "?" : username)
        let avatarURL = fireAvatarURL(
            avatarTemplate: avatarTemplate,
            size: 36,
            scale: UIScreen.main.scale,
            baseURLString: baseURLString
        )
        guard let avatarURL else { return }

        let request = FireRemoteImageRequest(url: avatarURL)
        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            imageView.image = cachedImage
            imageView.alpha = 1
            return
        }

        let currentGeneration = generation
        imageTask = Task { [weak self] in
            do {
                let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.apply(image: image, generation: currentGeneration)
                }
            } catch {
                return
            }
        }
    }

    func configureChannelGlyph(emoji: String?, title: String, colorHex: String?) {
        prepareForReuse()
        let glyph = emoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let glyph, !glyph.isEmpty, !glyph.hasPrefix(":") {
            monogramLabel.text = String(glyph.prefix(2))
            monogramLabel.font = UIFont.systemFont(ofSize: 20, weight: .regular)
        } else {
            monogramLabel.text = monogramForUsername(username: title.isEmpty ? "#" : title)
            monogramLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        }
        if let colorHex, let color = UIColor(fireHex: colorHex) {
            backgroundColor = color
        } else {
            backgroundColor = FireTopicListPalette.accent
        }
    }

    private func apply(image: UIImage, generation: UInt64) {
        guard self.generation == generation else { return }
        imageView.image = image
        imageView.alpha = 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Stay circular at every call-site size (home 36 / profile header 56).
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func configureSubviews() {
        clipsToBounds = true
        backgroundColor = FireTopicListPalette.accent

        monogramLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        monogramLabel.textColor = .white
        monogramLabel.textAlignment = .center
        monogramLabel.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFill
        imageView.alpha = 0
        imageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(monogramLabel)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            monogramLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            monogramLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            monogramLabel.topAnchor.constraint(equalTo: topAnchor),
            monogramLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
