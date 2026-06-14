import UIKit

final class FirePreheatGateWaitingViewController: UIViewController {
    private(set) var sessionStore: FireSessionStore?
    private var gateViewController: FirePreheatGateViewController?
    private let statusView = FireStartupOnboardingStatusView()
    private let onComplete: () -> Void
    private let onRequestLogin: (String?) -> Void

    init(
        sessionStore: FireSessionStore?,
        onComplete: @escaping () -> Void,
        onRequestLogin: @escaping (String?) -> Void
    ) {
        self.sessionStore = sessionStore
        self.onComplete = onComplete
        self.onRequestLogin = onRequestLogin
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FireStartupOnboardingPalette.background

        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.showLoading("正在准备登录态…")
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: view.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        if let sessionStore {
            installGate(with: sessionStore)
        }
    }

    func configure(with store: FireSessionStore) {
        sessionStore = store
        if isViewLoaded {
            installGate(with: store)
        }
    }

    private func installGate(with store: FireSessionStore) {
        guard gateViewController == nil else { return }
        statusView.removeFromSuperview()
        let gate = FirePreheatGateViewController(
            sessionStore: store,
            onComplete: onComplete,
            onRequestLogin: onRequestLogin
        )
        gateViewController = gate
        addChild(gate)
        view.addSubview(gate.view)
        gate.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gate.view.topAnchor.constraint(equalTo: view.topAnchor),
            gate.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gate.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gate.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        gate.didMove(toParent: self)
    }
}
