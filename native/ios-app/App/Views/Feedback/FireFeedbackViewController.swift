import PhotosUI
import SnapKit
import UIKit

/// In-app feedback form. Works without login.
/// Current submit path: system share sheet with report text + optional redacted diagnostics JSON.
@MainActor
final class FireFeedbackViewController: UIViewController {
    enum Category: String, CaseIterable {
        case bug = "bug"
        case crash = "crash"
        case performance = "performance"
        case ui = "ui"
        case suggestion = "suggestion"
        case other = "other"

        var title: String {
            switch self {
            case .bug: return "缺陷"
            case .crash: return "崩溃"
            case .performance: return "性能"
            case .ui: return "界面"
            case .suggestion: return "建议"
            case .other: return "其他"
            }
        }
    }

    private let appViewModel: FireAppViewModel
    private let source: String

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let categoryButton = UIButton(type: .system)
    private let titleField = UITextField()
    private let bodyView = UITextView()
    private let attachDiagnosticsSwitch = UISwitch()
    private let shakeSwitch = UISwitch()
    private let metaLabel = UILabel()
    private let submitButton = UIButton(type: .system)
    private let githubButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)

    private var selectedCategory: Category = .bug
    private var selectedImages: [UIImage] = []
    private let mediaStack = UIStackView()

    init(viewModel: FireAppViewModel, source: String) {
        self.appViewModel = viewModel
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "反馈与建议"
        view.backgroundColor = FireTheme.uiCanvas
        navigationItem.largeTitleDisplayMode = .never
        // Full-screen page: use system back when pushed; close only when we are
        // the root of a standalone modal stack (onboarding / pre-tab shell).
        configureNavigationChrome()

        configureLayout()
        populateMeta()
        refreshCategoryButton()
        attachDiagnosticsSwitch.isOn = true
        shakeSwitch.isOn = FireFeedbackPresenter.isShakeEnabled
        shakeSwitch.addTarget(self, action: #selector(shakeToggled), for: .valueChanged)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureNavigationChrome()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let leaving =
            isMovingFromParent
            || isBeingDismissed
            || navigationController?.isBeingDismissed == true
        if leaving {
            FireFeedbackPresenter.feedbackDidDismiss()
        }
    }

    private func configureNavigationChrome() {
        let nav = navigationController
        let isStackRoot = nav?.viewControllers.first === self
        let isPushed = (nav?.viewControllers.count ?? 0) > 1
        if isPushed {
            navigationItem.leftBarButtonItem = nil
            return
        }
        // Root of secondary full-screen stack or onboarding modal: offer close.
        if isStackRoot {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeTapped)
            )
        }
    }

    private func configureLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill
        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentLayoutGuide).offset(16)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-32)
            make.leading.equalTo(scrollView.frameLayoutGuide).offset(FireTheme.pageHorizontalInset)
            make.trailing.equalTo(scrollView.frameLayoutGuide).offset(-FireTheme.pageHorizontalInset)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-FireTheme.pageHorizontalInset * 2)
        }

        contentStack.addArrangedSubview(makeCaption("无需登录即可提交。当前会通过系统分享发送报告；自动建 GitHub Issue 即将接入。"))
        contentStack.addArrangedSubview(makeFieldLabel("类型"))
        categoryButton.contentHorizontalAlignment = .leading
        categoryButton.addTarget(self, action: #selector(categoryTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(categoryButton)

        contentStack.addArrangedSubview(makeFieldLabel("标题"))
        titleField.placeholder = "简要描述问题"
        titleField.borderStyle = .roundedRect
        titleField.font = .systemFont(ofSize: 16)
        titleField.returnKeyType = .next
        contentStack.addArrangedSubview(titleField)

        contentStack.addArrangedSubview(makeFieldLabel("详细说明 / 复现步骤"))
        bodyView.font = .systemFont(ofSize: 16)
        bodyView.layer.cornerRadius = 8
        bodyView.layer.borderWidth = 1 / UIScreen.main.scale
        bodyView.layer.borderColor = FireTheme.uiTertiaryInk.withAlphaComponent(0.35).cgColor
        bodyView.backgroundColor = FireTheme.uiSurface
        bodyView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        bodyView.isScrollEnabled = false
        bodyView.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(140)
        }
        contentStack.addArrangedSubview(bodyView)

        contentStack.addArrangedSubview(makeFieldLabel("截图（可选）"))
        let addMedia = UIButton(type: .system)
        addMedia.setTitle("添加截图", for: .normal)
        addMedia.addTarget(self, action: #selector(addMediaTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(addMedia)

        mediaStack.axis = .horizontal
        mediaStack.spacing = 8
        mediaStack.alignment = .center
        contentStack.addArrangedSubview(mediaStack)

        contentStack.addArrangedSubview(makeToggleRow(
            title: "附带脱敏诊断日志",
            subtitle: "不含登录 cookie / CSRF",
            control: attachDiagnosticsSwitch
        ))
        contentStack.addArrangedSubview(makeToggleRow(
            title: "摇一摇打开反馈",
            subtitle: "未登录界面也可使用",
            control: shakeSwitch
        ))

        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = FireTheme.uiTertiaryInk
        metaLabel.numberOfLines = 0
        contentStack.addArrangedSubview(metaLabel)

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = FireTheme.uiTertiaryInk
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        contentStack.addArrangedSubview(statusLabel)

        activity.hidesWhenStopped = true
        contentStack.addArrangedSubview(activity)

        var submitConfig = UIButton.Configuration.filled()
        submitConfig.title = "分享反馈报告"
        submitConfig.baseBackgroundColor = FireTheme.uiAccent
        submitButton.configuration = submitConfig
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(submitButton)

        var ghConfig = UIButton.Configuration.plain()
        ghConfig.title = "在浏览器打开 GitHub Issues"
        githubButton.configuration = ghConfig
        githubButton.addTarget(self, action: #selector(openGitHubTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(githubButton)
    }

    private func makeCaption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = FireTheme.uiSubtleInk
        label.numberOfLines = 0
        return label
    }

    private func makeFieldLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = FireTheme.uiSubtleInk
        return label
    }

    private func makeToggleRow(title: String, subtitle: String, control: UISwitch) -> UIView {
        let row = UIView()
        row.fireApplyCardStyle()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = FireTheme.uiInk
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = FireTheme.uiTertiaryInk
        subtitleLabel.numberOfLines = 0
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        row.addSubview(textStack)
        row.addSubview(control)
        textStack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.top.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-12)
            make.trailing.lessThanOrEqualTo(control.snp.leading).offset(-12)
        }
        control.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
        }
        return row
    }

    private func populateMeta() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let username = appViewModel.session.bootstrap.currentUsername
        let userLine = username.map { "LinuxDo: \($0)" } ?? "LinuxDo: 未登录"
        let device = UIDevice.current
        metaLabel.text = """
        \(userLine)
        App: \(version) (\(build)) · iOS \(device.systemVersion)
        设备: \(device.model) · 入口: \(source)
        """
    }

    @objc private func closeTapped() {
        dismiss(animated: true) {
            FireFeedbackPresenter.feedbackDidDismiss()
        }
    }

    @objc private func categoryTapped() {
        let sheet = UIAlertController(title: "反馈类型", message: nil, preferredStyle: .actionSheet)
        for category in Category.allCases {
            sheet.addAction(UIAlertAction(title: category.title, style: .default) { [weak self] _ in
                self?.selectedCategory = category
                self?.refreshCategoryButton()
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.sourceView = categoryButton
        present(sheet, animated: true)
    }

    private func refreshCategoryButton() {
        var config = UIButton.Configuration.gray()
        config.title = selectedCategory.title
        config.image = UIImage(systemName: "chevron.up.chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 8
        config.baseForegroundColor = FireTheme.uiInk
        categoryButton.configuration = config
    }

    @objc private func shakeToggled() {
        FireFeedbackPresenter.isShakeEnabled = shakeSwitch.isOn
    }

    @objc private func addMediaTapped() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = max(0, 3 - selectedImages.count)
        guard config.selectionLimit > 0 else {
            showStatus("最多 3 张截图")
            return
        }
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func openGitHubTapped() {
        UIApplication.shared.open(FireFeedbackPresenter.issuesURL)
    }

    @objc private func submitTapped() {
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = bodyView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty || !body.isEmpty else {
            showStatus("请填写标题或详细说明")
            return
        }

        submitButton.isEnabled = false
        activity.startAnimating()
        showStatus("正在准备反馈包…")

        Task { @MainActor in
            defer {
                submitButton.isEnabled = true
                activity.stopAnimating()
            }

            var items: [Any] = []
            let report = buildReportText(title: title, body: body)
            let reportURL = writeTempText(report, name: "fire-feedback-report.txt")
            items.append(reportURL)

            if attachDiagnosticsSwitch.isOn {
                do {
                    let export = try await appViewModel.exportFeedbackBundle(scenePhase: "active")
                    items.append(URL(fileURLWithPath: export.absolutePath))
                    showStatus("已附带脱敏诊断包 (\(export.fileName))")
                } catch {
                    showStatus("诊断包导出失败，将仅分享文字：\(error.localizedDescription)")
                }
            }

            for (index, image) in selectedImages.enumerated() {
                if let data = image.jpegData(compressionQuality: 0.85) {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("fire-feedback-\(index).jpg")
                    try? data.write(to: url, options: .atomic)
                    items.append(url)
                }
            }

            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = submitButton
            present(activity, animated: true)
        }
    }

    private func buildReportText(title: String, body: String) -> String {
        let category = selectedCategory
        let username = appViewModel.session.bootstrap.currentUsername ?? "anonymous"
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return """
        ## \(title.isEmpty ? "(no title)" : title)

        ### Type
        \(category.rawValue)

        ### Description
        \(body.isEmpty ? "(empty)" : body)

        ### Environment
        - Platform: ios
        - App: \(version) (\(build))
        - iOS: \(UIDevice.current.systemVersion)
        - Device: \(UIDevice.current.model)
        - LinuxDo: \(username)
        - Source: \(source)
        - Submitted: \(ISO8601DateFormatter().string(from: Date()))

        _Generated by Fire in-app feedback. Prefer attaching the redacted diagnostics JSON when available._
        """
    }

    private func writeTempText(_ text: String, name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private func showStatus(_ text: String) {
        statusLabel.isHidden = false
        statusLabel.text = text
    }

    private func refreshMediaStrip() {
        mediaStack.arrangedSubviews.forEach {
            mediaStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for image in selectedImages {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 8
            imageView.snp.makeConstraints { make in
                make.width.height.equalTo(64)
            }
            mediaStack.addArrangedSubview(imageView)
        }
    }
}

extension FireFeedbackViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in
                    guard let self else { return }
                    if self.selectedImages.count < 3 {
                        self.selectedImages.append(image)
                        self.refreshMediaStrip()
                    }
                }
            }
        }
    }
}
