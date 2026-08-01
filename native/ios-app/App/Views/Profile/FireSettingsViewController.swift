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

    private lazy var appearanceControl: FireUIKitAppearanceCapsuleControl = {
        let control = FireUIKitAppearanceCapsuleControl()
        // Seed from storage before first layout so the pill never paints on the
        // default `.system` segment when the user has another preference.
        control.selectedPreference = FireUIKitAppearanceCapsuleControl.normalizedForPicker(
            FireAppearancePreference(
                rawValue: UserDefaults.standard.string(forKey: FireTheme.appearancePreferenceStorageKey) ?? ""
            ) ?? .system
        )
        return control
    }()
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
            make.top.equalTo(scrollView.contentLayoutGuide.snp.top).offset(4)
            make.bottom.equalTo(scrollView.contentLayoutGuide.snp.bottom).offset(-24)
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
                    showsChevron: true,
                    iconWellColor: UIColor.systemIndigo
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
                        showsChevron: false,
                        iconWellColor: FireTheme.uiError
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
        // Environment owns UserDefaults write, window override, global chrome, and publish.
        let snapshot = FireAppearanceEnvironment.applyPreference(
            preference,
            window: view.window
        )
        applyAppearance(snapshot)
        syncAppearanceControl()
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

extension FireSettingsViewController: FireAppearanceApplying {
    func applyAppearance(_ snapshot: FireAppearanceSnapshot) {
        FireAppearanceTexture.applySnapshot(snapshot, to: view)
        FireAppearanceTexture.applySnapshot(snapshot, to: scrollView)
        // Cards pick up dynamic colors via adaptive UIColors on next layout.
        contentStack.arrangedSubviews.forEach { subview in
            if let card = subview as? FireUIKitSettingsCardView {
                card.setNeedsLayout()
            }
        }
        versionLabel.textColor = snapshot.tertiaryInk
        navigationController?.navigationBar.tintColor = snapshot.accent
    }
}
