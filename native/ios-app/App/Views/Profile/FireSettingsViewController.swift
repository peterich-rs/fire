import Combine
import SnapKit
import SwiftUI
import UIKit

/// Settings screen rebuilt to match the reference card language:
/// pure canvas, floating rounded cards, icon wells, capsule appearance control.
@MainActor
final class FireSettingsViewController: UIViewController {
    private let appViewModel: FireAppViewModel
    private let canLogout: Bool

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var cancellables: Set<AnyCancellable> = []

    private lazy var appearanceControl = FireUIKitAppearanceCapsuleControl()
    private lazy var diagnosticsCard = FireUIKitSettingsCardView()
    private lazy var signOutCard = FireUIKitSettingsCardView()
    private let versionLabel = UILabel()

    init(viewModel: FireAppViewModel, canLogout: Bool) {
        self.appViewModel = viewModel
        self.canLogout = canLogout
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent
        navigationController?.navigationBar.prefersLargeTitles = false

        configureScrollLayout()
        rebuildContent()
        bind()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Independent full-screen page chrome
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        syncAppearanceControl()
        rebuildContent()
    }

    private func configureScrollLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.backgroundColor = FireTheme.uiCanvas
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.alignment = .fill
        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentLayoutGuide.snp.top).offset(8)
            make.bottom.equalTo(scrollView.contentLayoutGuide.snp.bottom).offset(-28)
            make.leading.equalTo(scrollView.frameLayoutGuide.snp.leading).offset(FireTheme.pageHorizontalInset)
            make.trailing.equalTo(scrollView.frameLayoutGuide.snp.trailing).offset(-FireTheme.pageHorizontalInset)
            make.width.equalTo(scrollView.frameLayoutGuide.snp.width).offset(-FireTheme.pageHorizontalInset * 2)
        }

        appearanceControl.onChange = { [weak self] preference in
            self?.setAppearancePreference(preference)
        }

        versionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        versionLabel.textColor = FireTheme.uiTertiaryInk
        versionLabel.textAlignment = .center
        versionLabel.numberOfLines = 0
    }

    private func bind() {
        appViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildContent()
            }
            .store(in: &cancellables)
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // APPEARANCE
        contentStack.addArrangedSubview(makeSectionHeader("外观"))
        contentStack.setCustomSpacing(10, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(appearanceControl)
        contentStack.setCustomSpacing(FireTheme.sectionSpacing, after: appearanceControl)
        syncAppearanceControl()

        // DIAGNOSTICS
        contentStack.addArrangedSubview(makeSectionHeader("诊断"))
        contentStack.setCustomSpacing(10, after: contentStack.arrangedSubviews.last!)
        diagnosticsCard.setRows([
            (
                .init(
                    systemImage: "wrench.and.screwdriver.fill",
                    title: "开发者工具",
                    subtitle: "日志、网络与诊断导出",
                    showsChevron: true
                ),
                { [weak self] in self?.openDeveloperTools() }
            ),
        ])
        contentStack.addArrangedSubview(diagnosticsCard)
        contentStack.setCustomSpacing(FireTheme.sectionSpacing, after: diagnosticsCard)

        // SIGN OUT (standalone card)
        if canLogout {
            signOutCard.setRows([
                (
                    .init(
                        systemImage: "rectangle.portrait.and.arrow.right",
                        title: appViewModel.isLoggingOut ? "退出中…" : "退出登录",
                        showsChevron: false
                    ),
                    appViewModel.isLoggingOut ? nil : { [weak self] in self?.confirmLogout() }
                ),
            ])
            contentStack.addArrangedSubview(signOutCard)
            contentStack.setCustomSpacing(28, after: signOutCard)
        }

        versionLabel.text = versionText
        contentStack.addArrangedSubview(versionLabel)
    }

    private func makeSectionHeader(_ title: String) -> UIView {
        let host = UIView()
        let label = FireUIKitSectionHeaderLabel()
        label.setSectionTitle(title)
        host.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(4)
            make.trailing.equalToSuperview().offset(-4)
            make.top.equalToSuperview().offset(4)
            make.bottom.equalToSuperview()
        }
        return host
    }

    private func syncAppearanceControl() {
        appearanceControl.selectedPreference = FireUIKitAppearanceCapsuleControl.normalizedForPicker(
            appearancePreference
        )
    }

    private var appearancePreference: FireAppearancePreference {
        FireAppearancePreference(
            rawValue: UserDefaults.standard.string(forKey: FireTheme.appearancePreferenceStorageKey) ?? ""
        ) ?? .system
    }

    private func setAppearancePreference(_ preference: FireAppearancePreference) {
        // Picker only exposes dark / system / light (reference). OLED maps to dark.
        let normalized = FireUIKitAppearanceCapsuleControl.normalizedForPicker(preference)
        UserDefaults.standard.set(normalized.rawValue, forKey: FireTheme.appearancePreferenceStorageKey)
        applyAppearance(normalized)
        NotificationCenter.default.post(name: .fireAppearancePreferenceDidChange, object: normalized)
        FireTheme.applyGlobalAppearances()
        view.backgroundColor = FireTheme.uiCanvas
        scrollView.backgroundColor = FireTheme.uiCanvas
        // Don't rebuild whole page on theme change — only refresh chrome colors.
        contentStack.arrangedSubviews.forEach { view in
            if let card = view as? FireUIKitSettingsCardView {
                // Cards pick up dynamic colors via adaptive UIColors on next layout.
                card.setNeedsLayout()
            }
        }
        syncAppearanceControl()
    }

    private func applyAppearance(_ preference: FireAppearancePreference) {
        let window = view.window
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        switch preference {
        case .system:
            window?.overrideUserInterfaceStyle = .unspecified
        case .light:
            window?.overrideUserInterfaceStyle = .light
        case .dark, .oled:
            window?.overrideUserInterfaceStyle = .dark
        }
        FireUIKitSkeleton.applyThemeDefaults()
    }

    private func confirmLogout() {
        let alert = UIAlertController(
            title: "确认退出",
            message: "会先尝试通知服务端退出；即使网络请求失败，也会清空本地登录态并回到登录页。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出登录", style: .destructive) { [weak self] _ in
            self?.appViewModel.logout()
        })
        present(alert, animated: true)
    }

    private func openDeveloperTools() {
        let host = FireHosting.controller(
            rootView: FireDeveloperToolsView(viewModel: appViewModel),
            title: "开发者工具"
        )
        navigationController?.pushViewController(host, animated: true)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        let gitSha = (info?["FireGitSha"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shortSha: String? = {
            guard let gitSha, !gitSha.isEmpty, gitSha != "unknown" else { return nil }
            return String(gitSha.prefix(8))
        }()
        let base: String
        switch (version, build) {
        case let (v?, b?):
            base = "Fire \(v) (\(b))"
        case let (v?, nil):
            base = "Fire \(v)"
        case let (nil, b?):
            base = "Build \(b)"
        default:
            base = "Fire"
        }
        if let shortSha {
            return "\(base) · \(shortSha)"
        }
        return base
    }
}

extension Notification.Name {
    static let fireAppearancePreferenceDidChange = Notification.Name("fire.appearancePreferenceDidChange")
}
