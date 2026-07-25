import UIKit
import WebKit

enum FireCaptchaDialogResult {
    case success
    case needSecondFactor(SecondFactorRequirementState)
    case retryCloudflare
    case failure(LoginFailureState)
}

/// Form-sheet dialog that renders hCaptcha in a WKWebView and executes
/// `window.__fireLogin`. On success the presenter must capture cookies from the
/// still-alive `webView` before dismissing, then show host-owned sync loading.
@MainActor
final class FireCaptchaLoginDialogController: UIViewController {
    private(set) var webView: WKWebView!

    private let identifier: String
    private let password: String
    private let loginCoordinator: FireWebViewLoginCoordinator
    private let onResult: (FireCaptchaDialogResult) -> Void
    private let onCancel: () -> Void

    private var lastLoginHcaptchaToken: String?
    private var lastLoginSecondFactorToken: String?
    private var hasReportedResult = false
    private var didTearDownWebView = false
    private var loginResultTimeoutWorkItem: DispatchWorkItem?
    private let headerView = UIView()
    private let titleLabel = UILabel()

    /// Web-measured captcha content height (points). Drives the fit detent.
    private var reportedContentHeight: CGFloat = 180
    private var isChallengeExpanded = false
    /// Once the challenge opens, lock the first settled height so later observer
    /// noise cannot keep re-animating the sheet.
    private var lockedExpandedContentHeight: CGFloat?
    private var lastAppliedDetentIdentifier: UISheetPresentationController.Detent.Identifier?
    private var lastAppliedContentHeight: CGFloat = 0
    private var pendingDetentRefreshWorkItem: DispatchWorkItem?

    private static let loginResultTimeoutSeconds: TimeInterval = 30
    private static let headerHeight: CGFloat = 56
    private static let compactDetentIdentifier = UISheetPresentationController.Detent.Identifier("fire.captcha.compact")
    private static let fitDetentIdentifier = UISheetPresentationController.Detent.Identifier("fire.captcha.fit")

    var classifyResult: ((WebViewLoginPhaseState, UInt16, String) -> Void)?

    init(
        identifier: String,
        password: String,
        loginCoordinator: FireWebViewLoginCoordinator,
        onResult: @escaping (FireCaptchaDialogResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.identifier = identifier
        self.password = password
        self.loginCoordinator = loginCoordinator
        self.onResult = onResult
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        // Always present a white captcha chrome regardless of app dark mode.
        overrideUserInterfaceStyle = .light
        modalPresentationStyle = .pageSheet
        // Swipe-to-dismiss still routes through presentationControllerDidDismiss.
        presentationController?.delegate = self
        if let sheet = sheetPresentationController {
            // Start compact for the checkbox; expand to a content-fit detent when
            // hCaptcha opens its challenge UI (height comes from WebView JS).
            sheet.detents = makeSheetDetents()
            sheet.selectedDetentIdentifier = Self.compactDetentIdentifier
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            // Keep the login form behind the sheet undimmed / full color.
            sheet.largestUndimmedDetentIdentifier = Self.fitDetentIdentifier
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupHeader()
        setupWebView()
        loadMinimalLoginPage()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            tearDownWebViewIfNeeded()
        }
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .white

        // Extra top inset so the title sits in the header band, not tight under the grabber.
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "安全验证"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center

        view.addSubview(headerView)
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: headerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -16),
        ])
    }

    private func setupWebView() {
        let configuration = FireWebViewBrowserProfile.makeMinimalLoginConfiguration(
            messageHandler: FireCaptchaScriptMessageProxy(delegate: self)
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        // Challenge UI can be taller than the sheet; allow scrolling instead of clipping.
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.alwaysBounceVertical = true
        webView.isOpaque = true
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        FireWebViewBrowserProfile.configure(webView)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    fileprivate func markCaptchaReady(detail: String?) {
        switch detail {
        case "open":
            guard !isChallengeExpanded else { return }
            isChallengeExpanded = true
            // Stable seed until one settled measurement arrives — avoids multi-step bounce.
            if lockedExpandedContentHeight == nil {
                reportedContentHeight = 540
            }
            scheduleDetentRefresh(delay: 0.02, animated: true)
        case "close":
            isChallengeExpanded = false
            lockedExpandedContentHeight = nil
            reportedContentHeight = 160
            scheduleDetentRefresh(delay: 0.02, animated: true)
        default:
            break
        }
    }

    fileprivate func handleContentHeightMessage(_ body: Any?) {
        let height: CGFloat?
        let expanded: Bool?
        let reason: String?
        if let dict = body as? [String: Any] {
            if let number = dict["height"] as? NSNumber {
                height = CGFloat(truncating: number)
            } else if let value = dict["height"] as? CGFloat {
                height = value
            } else if let value = dict["height"] as? Double {
                height = CGFloat(value)
            } else {
                height = nil
            }
            expanded = dict["expanded"] as? Bool
            reason = dict["reason"] as? String
        } else if let number = body as? NSNumber {
            height = CGFloat(truncating: number)
            expanded = nil
            reason = nil
        } else {
            height = nil
            expanded = nil
            reason = nil
        }

        if let expanded {
            if expanded != isChallengeExpanded {
                isChallengeExpanded = expanded
                if !expanded {
                    lockedExpandedContentHeight = nil
                }
            }
        }

        if let height, height.isFinite, height > 0 {
            let expandedNow = isChallengeExpanded || expanded == true
            // Challenge card-only height; keep enough room so phase-1 checkbox stays fully covered.
            let capped = min(height, expandedNow ? 600 : 190)

            if expandedNow {
                // Lock the first solid challenge height; only grow if much taller content appears.
                if let locked = lockedExpandedContentHeight {
                    if capped > locked + 36 {
                        lockedExpandedContentHeight = capped
                        reportedContentHeight = capped
                    } else {
                        // Ignore shrink / jitter while expanded.
                        return
                    }
                } else if reason == "open-seed" {
                    // Seed only if we don't already have a lock; don't animate twice.
                    reportedContentHeight = capped
                } else {
                    lockedExpandedContentHeight = capped
                    reportedContentHeight = capped
                }
            } else {
                if abs(capped - reportedContentHeight) < 12 {
                    return
                }
                reportedContentHeight = capped
            }
        }

        // Debounce observer storms from hCaptcha mounting its challenge DOM.
        let delay: TimeInterval
        switch reason {
        case "open", "open-seed":
            delay = 0.05
        case "open-delayed", "resize", "mutate", "observe", "window":
            delay = 0.32
        case "close", "pass":
            delay = 0.05
        default:
            delay = isChallengeExpanded ? 0.28 : 0.12
        }
        scheduleDetentRefresh(delay: delay, animated: true)
    }

    private func scheduleDetentRefresh(delay: TimeInterval, animated: Bool) {
        pendingDetentRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshSheetDetents(animated: animated)
        }
        pendingDetentRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func makeSheetDetents() -> [UISheetPresentationController.Detent] {
        let compact = UISheetPresentationController.Detent.custom(
            identifier: Self.compactDetentIdentifier
        ) { context in
            // Checkbox-only chrome: a bit under half screen.
            min(max(context.maximumDetentValue * 0.42, 280), context.maximumDetentValue * 0.5)
        }
        let fit = UISheetPresentationController.Detent.custom(
            identifier: Self.fitDetentIdentifier
        ) { [weak self] context in
            guard let self else {
                return context.maximumDetentValue * 0.62
            }
            // Fit the challenge card; keep a floor tall enough that phase-1 UI cannot peek.
            let target = self.sheetChromeHeight() + min(self.reportedContentHeight, 600)
            return min(
                max(target, context.maximumDetentValue * 0.58),
                context.maximumDetentValue * 0.82
            )
        }
        // No `.large()` default path — challenge cards do not need full screen.
        return [compact, fit]
    }

    private func sheetChromeHeight() -> CGFloat {
        // Grabber air + header band. Sheet already owns home-indicator inset.
        6 + Self.headerHeight + 8
    }

    private func refreshSheetDetents(animated: Bool) {
        guard let sheet = sheetPresentationController else { return }
        let selected = isChallengeExpanded
            ? Self.fitDetentIdentifier
            : Self.compactDetentIdentifier
        let contentHeight = isChallengeExpanded
            ? (lockedExpandedContentHeight ?? reportedContentHeight)
            : reportedContentHeight

        // Skip no-op updates that would restart sheet animation mid-flight.
        if selected == lastAppliedDetentIdentifier,
           abs(contentHeight - lastAppliedContentHeight) < 20 {
            return
        }

        lastAppliedDetentIdentifier = selected
        lastAppliedContentHeight = contentHeight
        reportedContentHeight = contentHeight

        let apply = {
            sheet.detents = self.makeSheetDetents()
            sheet.selectedDetentIdentifier = selected
        }
        if animated {
            sheet.animateChanges(apply)
        } else {
            apply()
        }
    }

    private func tearDownWebViewIfNeeded() {
        guard !didTearDownWebView else { return }
        didTearDownWebView = true
        pendingDetentRefreshWorkItem?.cancel()
        pendingDetentRefreshWorkItem = nil
        [

            FireLoginScripts.hcaptchaPassMessageName,
            FireLoginScripts.hcaptchaErrorMessageName,
            FireLoginScripts.hcaptchaExpiredMessageName,
            FireLoginScripts.hcaptchaReadyMessageName,
            FireLoginScripts.hcaptchaContentHeightMessageName,
            FireLoginScripts.loginResultMessageName,
        ].forEach { name in
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
        webView?.stopLoading()
    }

    private func loadMinimalLoginPage() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await loginCoordinator.primeCookies(
                    into: webView,
                    targetURL: URL(string: "https://linux.do/")
                )
            } catch {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "warn",
                    target: "auth.login",
                    message: "captcha dialog cookie priming failed: \(error.localizedDescription)"
                )
            }

            let html = FireLoginScripts.minimalLoginHTML(
                hcaptchaSiteKey: FireLoginScripts.linuxDoHcaptchaSiteKey,
                hcaptchaCreateEndpoint: "/captcha/hcaptcha/create.json"
            )
            webView.loadHTMLString(html, baseURL: URL(string: "https://linux.do/"))
        }
    }

    func dispatchResult(_ result: FireCaptchaDialogResult) {
        reportResult(result)
    }

    func retryWithSecondFactor(_ token: String) {
        hasReportedResult = false
        lastLoginHcaptchaToken = nil
        lastLoginSecondFactorToken = token

        scheduleLoginResultTimeout(reason: "after second_factor")
        evaluateFireLogin(
            hcaptchaToken: nil,
            secondFactorToken: token,
            context: "second_factor"
        )
    }

    func retryAfterCloudflareRecovery() {
        guard lastLoginHcaptchaToken != nil || lastLoginSecondFactorToken != nil else {
            hasReportedResult = false
            return
        }

        hasReportedResult = false
        scheduleLoginResultTimeout(reason: "after cloudflare recovery")
        evaluateFireLogin(
            hcaptchaToken: lastLoginHcaptchaToken,
            secondFactorToken: lastLoginSecondFactorToken,
            context: "cloudflare_retry"
        )
    }

    fileprivate func runLogin(hcaptchaToken: String) {
        lastLoginHcaptchaToken = hcaptchaToken
        lastLoginSecondFactorToken = nil
        hasReportedResult = false
        isChallengeExpanded = false
        refreshSheetDetents(animated: true)
        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "hcaptcha_pass received; invoking __fireLogin token_len=\(hcaptchaToken.count)"
        )
        scheduleLoginResultTimeout(reason: "after hcaptcha_pass")
        evaluateFireLogin(
            hcaptchaToken: hcaptchaToken,
            secondFactorToken: nil,
            context: "hcaptcha_pass"
        )
    }

    private func evaluateFireLogin(
        hcaptchaToken: String?,
        secondFactorToken: String?,
        context: String
    ) {
        let invocation = FireLoginScripts.fireLoginInvocation(
            identifier: identifier,
            password: password,
            hcaptchaToken: hcaptchaToken,
            secondFactorToken: secondFactorToken
        )
        webView.evaluateJavaScript(invocation) { [weak self] _, error in
            guard let self else { return }
            if let error, !FireLoginScripts.isBenignEvaluateJavaScriptError(error) {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "error",
                    target: "auth.login",
                    message: "__fireLogin evaluateJavaScript failed (\(context)): \(error.localizedDescription)"
                )
                self.reportResult(.failure(Self.unknownFailure(message: error.localizedDescription)))
                return
            }
            if let error {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "__fireLogin evaluateJavaScript benign (\(context)): \(error.localizedDescription); awaiting login_result"
                )
            } else {
                FireAPMManager.shared.recordBreadcrumb(
                    level: "info",
                    target: "auth.login",
                    message: "__fireLogin evaluateJavaScript accepted (\(context)); awaiting login_result bridge"
                )
            }
        }
    }

    private func scheduleLoginResultTimeout(reason: String) {
        loginResultTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hasReportedResult else { return }
            FireAPMManager.shared.recordBreadcrumb(
                level: "error",
                target: "auth.login",
                message: "login_result timeout after \(Self.loginResultTimeoutSeconds)s (\(reason))"
            )
            self.reportResult(
                .failure(
                    Self.unknownFailure(message: "登录请求超时，请重试")
                )
            )
        }
        loginResultTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.loginResultTimeoutSeconds,
            execute: work
        )
    }

    fileprivate func showHcaptchaError(_ message: String) {
        // Status chrome was removed; keep the dialog open so the widget can be retried.
        FireAPMManager.shared.recordBreadcrumb(
            level: "warn",
            target: "auth.login",
            message: "hcaptcha error: \(message)"
        )
        isChallengeExpanded = false
        refreshSheetDetents(animated: true)
    }

    fileprivate func handleLoginResultJs(_ body: [String: Any]) {
        let phase: WebViewLoginPhaseState
        switch (body["phase"] as? String)?.lowercased() {
        case "csrf":
            phase = .csrf
        case "hcaptcha":
            phase = .hcaptcha
        case "session":
            phase = .session
        default:
            phase = .exception
        }

        let rawStatus = (body["status"] as? NSNumber)?.intValue
            ?? body["status"] as? Int
            ?? 0
        classifyResult?(phase, UInt16(clamping: rawStatus), (body["body"] as? String) ?? "")
    }

    private func reportResult(_ result: FireCaptchaDialogResult) {
        guard !hasReportedResult else { return }
        hasReportedResult = true
        loginResultTimeoutWorkItem?.cancel()
        loginResultTimeoutWorkItem = nil

        switch result {
        case .success, .needSecondFactor, .retryCloudflare:
            break
        case .failure:
            // Allow a subsequent captcha/login attempt from the same dialog if needed.
            hasReportedResult = false
            isChallengeExpanded = false
            refreshSheetDetents(animated: true)
        }

        FireAPMManager.shared.recordBreadcrumb(
            level: "info",
            target: "auth.login",
            message: "captcha dialog reportResult \(String(describing: result))"
        )
        onResult(result)
    }

    private func handleCancel() {
        guard !hasReportedResult else { return }
        hasReportedResult = true
        onCancel()
        if presentingViewController != nil {
            dismiss(animated: true)
        }
    }

    private static func unknownFailure(message: String) -> LoginFailureState {
        LoginFailureState(
            kind: .unknown,
            message: message,
            sentToEmail: nil,
            currentEmail: nil
        )
    }
}

extension FireCaptchaLoginDialogController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Grabber / interactive swipe-down path (no close button).
        handleCancel()
    }
}

private final class FireCaptchaScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var delegate: FireCaptchaLoginDialogController?

    init(delegate: FireCaptchaLoginDialogController) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let delegate else { return }

        switch message.name {
        case FireLoginScripts.hcaptchaPassMessageName:
            if let token = message.body as? String {
                Task { @MainActor in
                    delegate.runLogin(hcaptchaToken: token)
                }
            }
        case FireLoginScripts.hcaptchaReadyMessageName:
            let detail = message.body as? String
            Task { @MainActor in
                delegate.markCaptchaReady(detail: detail)
            }
        case FireLoginScripts.hcaptchaErrorMessageName:
            let message = (message.body as? String) ?? "人机验证失败"
            Task { @MainActor in
                delegate.showHcaptchaError(message)
            }
        case FireLoginScripts.hcaptchaExpiredMessageName:
            Task { @MainActor in
                delegate.showHcaptchaError("人机验证已过期，请重试")
            }
        case FireLoginScripts.hcaptchaContentHeightMessageName:
            let body = message.body
            Task { @MainActor in
                delegate.handleContentHeightMessage(body)
            }
        case FireLoginScripts.loginResultMessageName:
            if let body = message.body as? [String: Any] {
                Task { @MainActor in
                    delegate.handleLoginResultJs(body)
                }
            }
        default:
            break
        }
    }
}
