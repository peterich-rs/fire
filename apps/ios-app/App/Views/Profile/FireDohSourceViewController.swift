import UIKit

@MainActor
final class FireDohSourceViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onChange: ((DohSettingsState, [DohPresetState]) -> Void)?

    private let appViewModel: FireAppViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let enableSwitch = UISwitch()
    private let testButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    private var settings = DohSettingsState(enabled: false, endpointUrl: "")
    private var presets: [DohPresetState] = []
    private var isSaving = false
    private var isProbing = false

    init(viewModel: FireAppViewModel) {
        self.appViewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "DNS over HTTPS"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FireTheme.uiCanvas
        navigationController?.navigationBar.tintColor = FireTheme.uiAccent

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = FireTheme.uiCanvas
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        enableSwitch.addTarget(self, action: #selector(enableChanged), for: .valueChanged)

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "测试连接"
        buttonConfig.cornerStyle = .capsule
        testButton.configuration = buttonConfig
        testButton.addTarget(self, action: #selector(testTapped), for: .touchUpInside)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = FireTheme.uiTertiaryInk
        statusLabel.numberOfLines = 0
        statusLabel.text = "仅对 API 请求生效。关闭后使用系统 DNS。"

        tableView.tableFooterView = makeFooter()
        Task { await reload() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let footer = tableView.tableFooterView else { return }
        let target = footer.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if footer.frame.size != target {
            footer.frame.size = target
            tableView.tableFooterView = footer
        }
    }

    private func makeFooter() -> UIView {
        let stack = UIStackView(arrangedSubviews: [testButton, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let host = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 120))
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -16),
        ])
        return host
    }

    private func reload() async {
        do {
            presets = try await appViewModel.listDohPresets()
            settings = try await appViewModel.getDohSettings()
            enableSwitch.isOn = settings.enabled
            tableView.reloadData()
            onChange?(settings, presets)
        } catch {
            statusLabel.text = error.localizedDescription
        }
    }

    @objc private func enableChanged() {
        settings = DohSettingsState(enabled: enableSwitch.isOn, endpointUrl: settings.endpointUrl)
        persist()
    }

    @objc private func testTapped() {
        guard !isProbing else { return }
        isProbing = true
        statusLabel.text = "正在测试…"
        Task {
            defer { isProbing = false }
            do {
                let result = try await appViewModel.probeDohSettings(settings)
                if result.ok {
                    let addresses = result.resolvedAddresses.joined(separator: ", ")
                    statusLabel.text = "成功：\(result.host) → \(addresses)（\(result.elapsedMs)ms）"
                } else {
                    statusLabel.text = result.errorMessage ?? "测试失败"
                }
            } catch {
                statusLabel.text = error.localizedDescription
            }
        }
    }

    private func persist() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                settings = try await appViewModel.setDohSettings(settings)
                enableSwitch.isOn = settings.enabled
                tableView.reloadData()
                onChange?(settings, presets)
            } catch {
                statusLabel.text = error.localizedDescription
                enableSwitch.isOn = settings.enabled
            }
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : presets.count + 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "开关" : "解析源"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1 ? "自定义源必须是 https:// 开头的 DoH URL。预设源会用内置 IP 启动，避免系统 DNS 污染。" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        if indexPath.section == 0 {
            content.text = "使用 DoH"
            content.secondaryText = "加密 DNS 查询，改善连接稳定性"
            cell.accessoryView = enableSwitch
            cell.selectionStyle = .none
        } else if indexPath.row < presets.count {
            let preset = presets[indexPath.row]
            content.text = preset.displayName
            content.secondaryText = preset.endpointUrl
            if settings.endpointUrl == preset.endpointUrl {
                cell.accessoryType = .checkmark
            }
        } else {
            content.text = "自定义"
            let isCustom = presets.allSatisfy { $0.endpointUrl != settings.endpointUrl }
            content.secondaryText = isCustom && !settings.endpointUrl.isEmpty
                ? settings.endpointUrl
                : "输入自己的 DoH 地址"
            cell.accessoryType = isCustom ? .checkmark : .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        if indexPath.row < presets.count {
            let preset = presets[indexPath.row]
            settings = DohSettingsState(enabled: settings.enabled, endpointUrl: preset.endpointUrl)
            persist()
            return
        }
        presentCustomURLPrompt()
    }

    private func presentCustomURLPrompt() {
        let alert = UIAlertController(
            title: "自定义 DoH",
            message: "例如 https://dns.alidns.com/dns-query",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.text = self.settings.endpointUrl
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            guard let self else { return }
            let raw = alert.textFields?.first?.text ?? ""
            self.settings = DohSettingsState(enabled: self.settings.enabled, endpointUrl: raw)
            self.persist()
        })
        present(alert, animated: true)
    }
}
