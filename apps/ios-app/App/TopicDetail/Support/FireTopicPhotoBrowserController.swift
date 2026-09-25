import JXPhotoBrowser
import Photos
import UIKit

final class FireTopicPhotoBrowserController: JXPhotoBrowserViewController, JXPhotoBrowserDelegate {
    private enum PhotoSaveError: Error {
        case unknownFailure
    }

    private let image: FireCookedImage
    private let imageRequest: FireRemoteImageRequest
    private let toolbar = UIStackView()
    private let statusStack = UIStackView()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private weak var activeCell: JXZoomImageCell?
    private var loadedImage: UIImage?
    private var loadTask: Task<Void, Never>?

    init(image: FireCookedImage) {
        self.image = image
        self.imageRequest = FireTopicImageRequestBuilder.cookedImageRequest(image)
        super.init(nibName: nil, bundle: nil)
        delegate = self
        initialIndex = 0
        isLoopingEnabled = false
        transitionType = .fade
        itemSpacing = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureOverlayControls()
        showLoading()
    }

    func numberOfItems(in browser: JXPhotoBrowserViewController) -> Int {
        1
    }

    func photoBrowser(
        _ browser: JXPhotoBrowserViewController,
        cellForItemAt index: Int,
        at indexPath: IndexPath
    ) -> JXPhotoBrowserAnyCell {
        browser.dequeueReusableCell(
            withReuseIdentifier: JXZoomImageCell.reuseIdentifier,
            for: indexPath
        )
    }

    func photoBrowser(
        _ browser: JXPhotoBrowserViewController,
        willDisplay cell: JXPhotoBrowserAnyCell,
        at index: Int
    ) {
        guard let photoCell = cell as? JXZoomImageCell else { return }
        photoCell.imageView.contentMode = .scaleAspectFit
        photoCell.imageView.accessibilityLabel = image.altText?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("帖子图片")
        activeCell = photoCell
        if let loadedImage {
            photoCell.imageView.image = loadedImage
            photoCell.adjustImageViewFrame()
            hideStatus()
        } else {
            photoCell.imageView.image = nil
            loadImage()
        }
    }

    func photoBrowser(
        _ browser: JXPhotoBrowserViewController,
        didEndDisplaying cell: JXPhotoBrowserAnyCell,
        at index: Int
    ) {
        if activeCell === cell {
            activeCell = nil
        }
    }

    private func configureOverlayControls() {
        toolbar.axis = .horizontal
        toolbar.alignment = .center
        toolbar.distribution = .equalSpacing
        toolbar.spacing = 12
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        toolbar.addArrangedSubview(controlButton(systemName: "xmark", action: #selector(closeTapped)))
        toolbar.addArrangedSubview(UIView())
        toolbar.addArrangedSubview(controlButton(systemName: "square.and.arrow.up", action: #selector(shareTapped)))
        toolbar.addArrangedSubview(controlButton(systemName: "arrow.down.to.line", action: #selector(saveTapped)))

        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 12
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusStack)

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        retryButton.setTitle("重试", for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.tintColor = .white
        statusStack.addArrangedSubview(activityIndicator)
        statusStack.addArrangedSubview(statusLabel)
        statusStack.addArrangedSubview(retryButton)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            statusStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func controlButton(systemName: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: systemName)
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.42)
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 42).isActive = true
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return button
    }

    private func loadImage() {
        loadTask?.cancel()
        showLoading()
        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: imageRequest) {
            applyLoadedImage(cachedImage)
            return
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolvedImage = try await FireRemoteImagePipeline.shared.loadImage(for: imageRequest)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.applyLoadedImage(resolvedImage)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.showFailure()
                }
            }
        }
    }

    private func showLoading() {
        statusStack.isHidden = false
        retryButton.isHidden = true
        statusLabel.text = "图片加载中..."
        activityIndicator.startAnimating()
    }

    private func showFailure() {
        loadedImage = nil
        activeCell?.imageView.image = nil
        statusStack.isHidden = false
        retryButton.isHidden = false
        statusLabel.text = "图片加载失败"
        activityIndicator.stopAnimating()
    }

    private func hideStatus() {
        statusStack.isHidden = true
        activityIndicator.stopAnimating()
    }

    private func applyLoadedImage(_ image: UIImage) {
        loadedImage = image
        activeCell?.imageView.image = image
        activeCell?.adjustImageViewFrame()
        hideStatus()
    }

    @objc private func retryTapped() {
        loadImage()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func shareTapped() {
        Task { @MainActor in
            guard let image = await resolvedToolbarImage() else { return }
            let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            present(controller, animated: true)
        }
    }

    @objc private func saveTapped() {
        Task { @MainActor in
            guard let image = await resolvedToolbarImage() else { return }
            let status = await photoLibraryAuthorizationStatus()
            guard status == .authorized || status == .limited else {
                presentAlert(title: "无法保存到相册", message: "Fire 需要照片权限才能保存当前图片。")
                return
            }
            do {
                try await saveImageToPhotoLibrary(image)
                presentAlert(title: "已保存到相册", message: "当前帖子图片已经保存。")
            } catch {
                presentAlert(title: "保存失败", message: "系统暂时无法写入相册，请稍后再试。")
            }
        }
    }

    @MainActor
    private func resolvedToolbarImage() async -> UIImage? {
        if let loadedImage {
            return loadedImage
        }
        do {
            let image = try await FireRemoteImagePipeline.shared.loadImage(for: imageRequest)
            applyLoadedImage(image)
            return image
        } catch {
            showFailure()
            return nil
        }
    }

    private func photoLibraryAuthorizationStatus() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func saveImageToPhotoLibrary(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoSaveError.unknownFailure)
                }
            }
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        present(alert, animated: true)
    }
}
