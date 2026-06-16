# Native Login Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic `FireLoginWebViewController` with a pure-native `FireLoginViewController` ( UIKit programmatic ) + a separate `FireCaptchaLoginDialogController` for hCaptcha, fixing the login flow ordering so verification only happens after the user enters credentials and taps login.

**Architecture:** Two-VC split aligned with fluxdo's `LoginPage` + `WebViewLoginDialog`. `FireLoginViewController` owns the native form, presents the captcha dialog, and coordinates the flow. `FireAppViewModel` exposes async capabilities (CF clearance, cookie priming, classify, finalize) but does NOT present UI. The captcha dialog keeps its WKWebView alive until `completeJsLogin` extracts cookies.

**Tech Stack:** UIKit (programmatic), WKWebView, Rust/UniFFI boundary (unchanged), Texture (not used for login).

**Spec:** `docs/superpowers/specs/2026-06-16-native-login-page-redesign-design.md`

---

## File Structure

| File | Responsibility |
|------|----------------|
| `native/ios-app/App/Views/Other/FireLoginViewController.swift` | Pure-native login page: logo, credential inputs, remember-password checkbox, login button, forgot-password link, "other login methods" button. Presents captcha dialog + handles results. |
| `native/ios-app/App/Views/Other/FireCaptchaLoginDialogController.swift` | Form-sheet dialog containing WKWebView for hCaptcha + `__fireLogin` execution. Exposes live `webView` for cookie extraction. Supports `retryWithSecondFactor`. |
| `native/ios-app/App/ViewModels/FireAppViewModel.swift` | Modified: `openLogin()` simplified, new `ensureCloudflareClearance()` / `loginCoordinatorForDialog()` / `probeLoginSyncReadiness(from:)`, `completeMinimalLogin` gains `rememberCredential` param. |
| `native/ios-app/App/Core/FireRootCoordinator.swift` | Modified: present `FireLoginViewController` instead of `FireLoginWebViewController`. |
| `native/ios-app/App/Views/Other/FireLoginWebView.swift` | **Deleted.** |

**Preserved (no changes):**
- `FireWebViewBrowserProfile.swift` — `minimalLoginHTML`, `__fireLogin`, `makeMinimalLoginConfiguration`
- `FireWebViewLoginCoordinator.swift` — `completeJsLogin(from:)`, `primeCookies(into:)`
- `FireSessionStore.swift` — `finalizeLoginFromWebView`, `classifyWebviewLoginResult`, `saveLoginCredential`
- `FireAuthCookieKeychainStore.swift` — `FireSavedCredential`
- `FireCloudflareChallengeCoordinator` — `completeManualVerification`
- All Rust/UniFFI boundary code

---

## Phase 1: Native Login Page + Login Flow (Complete Deliverable)

### Task 1: Create FireCaptchaLoginDialogController

**Files:**
- Create: `native/ios-app/App/Views/Other/FireCaptchaLoginDialogController.swift`

**Context:** This dialog is a `.pageSheet` modal containing a WKWebView. It loads `FireLoginScripts.minimalLoginHTML` to render the hCaptcha widget. When hCaptcha passes, JS auto-calls `window.__fireLogin(id, pwd, token)` which does `fetch /session/csrf → POST /hcaptcha/create → POST /session.json`. Results come back via `webkit.messageHandlers.login_result`. The WKWebView must stay alive for cookie extraction by `completeJsLogin(from:)`.

The dialog reuses `FireWebViewBrowserProfile.makeMinimalLoginConfiguration` and `FireLoginScripts.fireLoginInvocation` from the existing codebase.

- [ ] **Step 1: Create the dialog VC skeleton**

Create `native/ios-app/App/Views/Other/FireCaptchaLoginDialogController.swift`:

```swift
import UIKit
import WebKit

/// Result delivered to the presenting VC when the login JS completes.
enum FireCaptchaDialogResult {
    case success
    case needSecondFactor(SecondFactorRequirementState)
    case retryCloudflare
    case failure(LoginFailureState)
}

/// Form-sheet dialog that renders hCaptcha in a WKWebView and executes
/// `window.__fireLogin`. The WKWebView stays alive until the presenter
/// extracts cookies via `completeJsLogin(from:)`.
///
/// On success the presenter MUST call `completeMinimalLogin(from: dialog.webView, ...)`
/// before dismissing this dialog — otherwise the live WebView is destroyed
/// and cookies cannot be extracted.
final class FireCaptchaLoginDialogController: UIViewController {

    // MARK: - Public Properties

    /// The live WKWebView. Presenters read cookies from this after `.success`.
    private(set) var webView: WKWebView!

    // MARK: - Private Properties

    private let identifier: String
    private let password: String
    private let loginCoordinator: FireWebViewLoginCoordinator
    private let onResult: (FireCaptchaDialogResult) -> Void
    private let onCancel: () -> Void

    private var lastLoginHcaptchaToken: String?
    private var lastLoginSecondFactorToken: String?
    private var hasReportedResult = false
    private var titleLabel: UILabel!
    private var closeButton: UIButton!
    private var statusLabel: UILabel!
    private var activityIndicator: UIActivityIndicatorView!

    /// Set by the presenting VC before presenting. Called when JS posts
    /// a login_result message to classify the raw phase/status/body.
    var classifyResult: ((WebViewLoginPhaseState, UInt16, String) -> Void)?

    // MARK: - Init

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
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupWebView()
        setupStatusLabel()
        loadMinimalLoginPage()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        let navBar = UINavigationBar()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        let navItem = UINavigationItem(title: "安全验证")
        let closeAction = UIAction(title: "关闭", image: UIImage(systemName: "xmark")) { [weak self] _ in
            self?.handleCancel()
        }
        navItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, primaryAction: closeAction)
        navBar.items = [navItem]
        view.addSubview(navBar)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupWebView() {
        let configuration = FireWebViewBrowserProfile.makeMinimalLoginConfiguration(
            messageHandler: FireCaptchaScriptMessageProxy(delegate: self)
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.isScrollEnabled = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupStatusLabel() {
        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "正在加载验证…"
        view.addSubview(statusLabel)

        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: webView.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
        ])
    }

    // MARK: - Load

    private func loadMinimalLoginPage() {
        // Prime cookies into the WebView store before loading HTML
        // Uses loginCoordinator.primeCookies which reads canonical cookies from Rust
        Task {
            do {
                try await loginCoordinator.primeCookies(
                    into: webView,
                    targetURL: URL(string: "https://linux.do/")
                )
            } catch {
                // Non-fatal: CF retry path re-primes later
            }
            await MainActor.run {
                let html = FireLoginScripts.minimalLoginHTML(
                    hcaptchaSiteKey: FireLoginScripts.linuxDoHcaptchaSiteKey,
                    hcaptchaCreateEndpoint: "/captcha/hcaptcha/create.json"
                )
                self.webView.loadHTMLString(html, baseURL: URL(string: "https://linux.do/"))
            }
        }
    }

    // MARK: - Public Retry

    /// Retry login with a 2FA TOTP code. Uses the same live WebView — the
    /// `h_captcha_temp_id` cookie is still valid for the short retry window.
    func retryWithSecondFactor(_ token: String) {
        hasReportedResult = false
        lastLoginHcaptchaToken = nil
        lastLoginSecondFactorToken = token
        statusLabel.text = "正在验证…"
        activityIndicator.startAnimating()
        let invocation = FireLoginScripts.fireLoginInvocation(
            identifier: identifier,
            password: password,
            hcaptchaToken: nil,
            secondFactorToken: token
        )
        webView.evaluateJavaScript(invocation) { [weak self] _, error in
            if let error {
                self?.reportResult(.failure(LoginFailureState(
                    kind: .unknown,
                    message: error.localizedDescription,
                    sentToEmail: nil,
                    currentEmail: nil
                )))
            }
        }
    }

    // MARK: - Private

    private func runLogin(hcaptchaToken: String) {
        lastLoginHcaptchaToken = hcaptchaToken
        lastLoginSecondFactorToken = nil
        statusLabel.text = "正在登录…"
        activityIndicator.startAnimating()
        let invocation = FireLoginScripts.fireLoginInvocation(
            identifier: identifier,
            password: password,
            hcaptchaToken: hcaptchaToken,
            secondFactorToken: nil
        )
        webView.evaluateJavaScript(invocation) { [weak self] _, error in
            if let error {
                self?.reportResult(.failure(LoginFailureState(
                    kind: .unknown,
                    message: error.localizedDescription,
                    sentToEmail: nil,
                    currentEmail: nil
                )))
            }
        }
    }

    private func reportResult(_ result: FireCaptchaDialogResult) {
        guard !hasReportedResult else { return }
        hasReportedResult = true
        activityIndicator.stopAnimating()
        switch result {
        case .success:
            statusLabel.text = "验证成功"
        case .needSecondFactor:
            statusLabel.text = ""
        case .retryCloudflare:
            statusLabel.text = "正在恢复网络…"
        case .failure(let failure):
            statusLabel.text = failure.message ?? "登录失败"
            statusLabel.textColor = .systemRed
            // Allow retry: reset hCaptcha
            hasReportedResult = false
        }
        onResult(result)
    }

    private func handleCancel() {
        onCancel()
        dismiss(animated: true)
    }

    // MARK: - Deinit

    deinit {
        webView?.stopLoading()
    }
}

// MARK: - Script Message Handling

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
            // JS posts the token as a plain string: postNative('hcaptcha_pass', token)
            if let token = message.body as? String {
                delegate.runLoginInternal(hcaptchaToken: token)
            }
        case FireLoginScripts.hcaptchaErrorMessageName:
            // JS posts error as string
            let msg = (message.body as? String) ?? "人机验证失败"
            delegate.showHcaptchaError(msg)
        case FireLoginScripts.hcaptchaExpiredMessageName:
            delegate.showHcaptchaError("人机验证已过期，请重试")
        case FireLoginScripts.loginResultMessageName:
            if let body = message.body as? [String: Any] {
                delegate.handleLoginResultJs(body)
            }
        default:
            break
        }
    }
}

// MARK: - Internal methods for message proxy access
//
// These methods are called by FireCaptchaScriptMessageProxy. They must be
// on the main class (not an extension) because they access private state.

extension FireCaptchaLoginDialogController {
    func runLoginInternal(hcaptchaToken: String) {
        runLogin(hcaptchaToken: hcaptchaToken)
    }

    func showHcaptchaError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
            self?.statusLabel.textColor = .systemRed
        }
    }

    func handleLoginResultJs(_ body: [String: Any]) {
        // Parse JS result body into phase/status/body for classification
        // phase is a string from JS: "csrf" | "hcaptcha" | "session" | "exception"
        let phaseStr = (body["phase"] as? String) ?? "exception"
        let phase: WebViewLoginPhaseState
        switch phaseStr {
        case "csrf": phase = .csrf
        case "hcaptcha": phase = .hcaptcha
        case "session": phase = .session
        default: phase = .exception
        }
        let status = UInt16((body["status"] as? Int) ?? 0)
        let bodyStr = (body["body"] as? String) ?? ""
        classifyResult?(phase, status, bodyStr)
    }
}
```

Note: The dialog receives a `FireWebViewLoginCoordinator` instance for cookie priming. The coordinator's `primeCookies(into:targetURL:)` method reads canonical cookies from Rust and executes them against the WebView's `httpCookieStore`. The WKWebView must stay alive for cookie extraction by `completeJsLogin(from:)`.

- [ ] **Step 2: Verify it compiles**

Run: `xcodegen generate --spec native/ios-app/project.yml && xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

Expected: Build errors only from the new file (referencing types that don't exist yet or priming API mismatch). Fix any type mismatches against the actual `FireWebViewBrowserProfile` / `FireWebViewLoginCoordinator` APIs.

- [ ] **Step 3: Regenerate Xcode project and commit**

```bash
xcodegen generate --spec native/ios-app/project.yml
git add native/ios-app/App/Views/Other/FireCaptchaLoginDialogController.swift native/ios-app/Fire.xcodeproj/project.pbxproj
git commit -m "feat(login): add FireCaptchaLoginDialogController for hCaptcha + login request"
```

---

### Task 2: Add ViewModel Async Capabilities

**Files:**
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`

**Context:** The ViewModel currently has `prepareMinimalAuthWebView(_:)` (line 427-474) which does CF check + prime + load at page open. We need to split this into discrete async capabilities that the VC calls on-demand. We also need to add `rememberCredential` to `completeMinimalLogin`.

The existing `completeLoginCloudflareChallenge(sessionStore:)` (line 359-381) and `recoverLoginCloudflareChallenge(in:)` (line 348-357) already contain CF logic we can reuse.

- [ ] **Step 1: Add `ensureCloudflareClearance()` async method**

In `FireAppViewModel.swift`, add a new method near the existing CF methods (after line 381):

```swift
/// Checks cf_clearance and runs CF challenge if missing.
/// Returns true on success, false on failure or user cancellation.
func ensureCloudflareClearance() async -> Bool {
    do {
        let sessionStore = try await sessionStoreValue()
        if try await sessionStore.snapshot().readiness.hasCloudflareClearance {
            return true
        }

        try await completeLoginCloudflareChallenge(sessionStore: sessionStore)
        try await Task.sleep(for: .milliseconds(1_500))
        return try await sessionStore.snapshot().readiness.hasCloudflareClearance
    } catch {
        errorMessage = error.localizedDescription
        return false
    }
}
```

- [ ] **Step 2: Add `loginCoordinatorForDialog()` accessor**

The captcha dialog needs a `FireWebViewLoginCoordinator` instance for cookie priming. Add a simple accessor:

Add after `ensureCloudflareClearance()`:

```swift
/// Returns the login coordinator for the captcha dialog to use for priming.
func loginCoordinatorForDialog() async throws -> FireWebViewLoginCoordinator {
    try await loginCoordinatorValue()
}

/// Probes whether a full WebView fallback page has enough captured data
/// for the existing completeLogin(from:) finalizer.
func probeLoginSyncReadiness(from webView: WKWebView) async throws -> FireLoginSyncReadiness {
    let loginCoordinator = try await loginCoordinatorValue()
    return try await loginCoordinator.probeLoginSyncReadiness(from: webView)
}
```

- [ ] **Step 3: Add `rememberCredential` parameter to `completeMinimalLogin`**

Modify `completeMinimalLogin` at line 293-339. Change the signature and the save logic:

```swift
func completeMinimalLogin(
    from webView: WKWebView,
    identifier: String,
    password: String,
    rememberCredential: Bool
) {
    guard !isSyncingLoginSession else {
        return
    }

    isSyncingLoginSession = true
    Task {
        defer { isSyncingLoginSession = false }

        do {
            try await FireAPMManager.shared.withSpan(.authLoginSync) {
                let loginCoordinator = try await loginCoordinatorValue()
                let sessionStore = try await sessionStoreValue()
                errorMessage = nil
                await applySession(
                    try await loginCoordinator.completeJsLogin(
                        from: webView,
                        identifier: identifier
                    ),
                    activateMessageBus: false
                )
                if rememberCredential {
                    try await sessionStore.saveLoginCredential(
                        username: identifier,
                        password: password
                    )
                    savedLoginCredential = try await sessionStore.loadSavedCredential()
                } else {
                    // User unchecked "remember password" — clear old saved credentials
                    // so the next login page open does not auto-fill.
                    try await sessionStore.clearSavedCredential()
                    savedLoginCredential = nil
                }
                FireCfClearanceRefreshService.shared.setLoginStateConfirmed(true)
                try await sessionStore.triggerAppStateRefresh(
                    .loginCompleted,
                    handler: appStateRefreshCoordinator
                )
                setAuthPresentationState(nil)
                canSyncLoginSession = false
                cachedLoginSyncReadiness = nil
            }
        } catch {
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}
```

Key change: `saveLoginCredential` is now inside `if rememberCredential { }`, and when unchecked `clearSavedCredential()` is called to remove any previously saved credentials. Product semantic: unchecking "remember password" means the next login page open will not auto-fill.

- [ ] **Step 4: Add `classifyLoginResult` helper for dialog**

Add a method that the VC can call to classify a raw login_result JS body. Keep this helper returning the shared `WebViewLoginDecisionState`; the UIKit-only `FireCaptchaDialogResult` mapping stays inside `FireLoginViewController`, so `FireAppViewModel` does not depend on UI types. The `WebViewLoginJsResultState` takes a `WebViewLoginPhaseState` enum (`.csrf`/`.hcaptcha`/`.session`/`.exception`), a `UInt16` status, and a `String` body:

```swift
/// Classifies a raw login_result JS body into the shared WebView decision.
func classifyLoginResult(
    phase: WebViewLoginPhaseState,
    status: UInt16,
    body: String
) async throws -> WebViewLoginDecisionState {
    let result = WebViewLoginJsResultState(
        phase: phase,
        status: status,
        body: body
    )
    return try await classifyWebViewLoginResult(result)
}
```

- [ ] **Step 5: Simplify `openLogin()`**

Modify `openLogin()` at line 229-255 to remove the WebView preload. Keep only state + credential load:

```swift
func openLogin() {
    guard authPresentationState == nil else { return }
    authPresentationState = .login
    Task {
        do {
            let sessionStore = try await sessionStoreValue()
            savedLoginCredential = try await sessionStore.loadSavedCredential()
            _ = try await loginCoordinatorValue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 6: Verify it compiles**

Run: `xcodegen generate --spec native/ios-app/project.yml && xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

Expected: Build may still fail because `FireLoginWebViewController` references the old `completeMinimalLogin(from:identifier:password:)` signature. That's OK — Task 4 will delete that file.

- [ ] **Step 7: Commit**

```bash
git add native/ios-app/App/ViewModels/FireAppViewModel.swift
git commit -m "feat(login): add async login capabilities to ViewModel

- ensureCloudflareClearance() for on-demand CF check
- loginCoordinatorForDialog() exposes the authoritative login coordinator
- probeLoginSyncReadiness(from:) supports full WebView fallback finalization
- completeMinimalLogin gains rememberCredential param
- classifyLoginResult() returns shared WebViewLoginDecisionState
- openLogin() simplified, no WebView preload"
```

---

### Task 3: Create FireLoginViewController

**Files:**
- Create: `native/ios-app/App/Views/Other/FireLoginViewController.swift`

**Context:** This is the pure-native login page. Layout: logo (top), credential inputs, remember-password checkbox, login button, forgot-password link, "other login methods" button. The VC owns the login flow orchestration: calls ViewModel async capabilities, presents the captcha dialog, handles results.

- [ ] **Step 1: Create the login VC with layout**

Create `native/ios-app/App/Views/Other/FireLoginViewController.swift`:

```swift
import UIKit
import WebKit
import Combine

/// Pure-native login page. No WebView in this VC.
/// Presents `FireCaptchaLoginDialogController` for hCaptcha + login request.
final class FireLoginViewController: UIViewController {

    // MARK: - Dependencies

    private let viewModel: FireAppViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let logoImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let identifierField = UITextField()
    private let passwordField = UITextField()
    private let rememberSwitch = UISwitch()
    private let rememberLabel = UILabel()
    private let loginButton = UIButton(type: .system)
    private let forgotPasswordButton = UIButton(type: .system)
    private let dividerLabel = UILabel()
    private let otherMethodsButton = UIButton(type: .system)
    private let errorBannerLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    // MARK: - Login Flow State

    private var captchaDialog: FireCaptchaLoginDialogController?
    private var cfRetryUsed = false
    private var pendingIdentifier: String = ""
    private var pendingPassword: String = ""
    private var pendingRememberCredential: Bool = false
    private var hasShownSecondFactor = false

    // MARK: - Init

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigation()
        setupScrollView()
        setupLogo()
        setupCredentialFields()
        setupRememberPassword()
        setupLoginButton()
        setupForgotPassword()
        setupOtherMethods()
        setupErrorBanner()
        setupActivityIndicator()
        observeViewModelState()
    }

    // MARK: - ViewModel State

    private func observeViewModelState() {
        observeSavedCredential()
        observeLoginErrorsAndSyncingState()
    }

    /// Auto-fills credentials whenever they load (openLogin loads them asynchronously).
    private func observeSavedCredential() {
        viewModel.$savedLoginCredential
            .receive(on: RunLoop.main)
            .sink { [weak self] credential in
                guard let credential else { return }
                self?.identifierField.text = credential.username
                self?.passwordField.text = credential.password
                self?.rememberSwitch.isOn = true
                self?.updateLoginButtonState()
            }
            .store(in: &cancellables)
    }

    /// Existing ViewModel finalization APIs are fire-and-forget. Observe their
    /// published state so the native controller can clear loading UI and surface
    /// finalization failures instead of leaving the sheet spinning.
    private func observeLoginErrorsAndSyncingState() {
        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .sink { [weak self] message in
                guard let self, self.captchaDialog != nil else { return }
                self.setLoginLoading(false)
                self.dismissCaptchaDialog()
                self.showErrorBanner(message)
            }
            .store(in: &cancellables)

        viewModel.$isSyncingLoginSession
            .receive(on: RunLoop.main)
            .sink { [weak self] isSyncing in
                guard let self, !isSyncing, self.viewModel.authPresentationState != nil else { return }
                self.setLoginLoading(false)
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupNavigation() {
        title = "登录 LinuxDo"
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func setupLogo() {
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.image = UIImage(systemName: "flame.fill")
        logoImageView.tintColor = .systemOrange
        logoImageView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Fire"
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "LinuxDo 社区客户端"
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center

        contentView.addSubview(logoImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            logoImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 48),
            logoImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoImageView.widthAnchor.constraint(equalToConstant: 72),
            logoImageView.heightAnchor.constraint(equalToConstant: 72),

            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
    }

    private func setupCredentialFields() {
        identifierField.translatesAutoresizingMaskIntoConstraints = false
        identifierField.placeholder = "用户名或邮箱"
        identifierField.borderStyle = .roundedRect
        identifierField.autocapitalizationType = .none
        identifierField.autocorrectionType = .no
        identifierField.textContentType = .username
        identifierField.returnKeyType = .next
        identifierField.addTarget(self, action: #selector(textFieldsChanged), for: .editingChanged)

        passwordField.translatesAutoresizingMaskIntoConstraints = false
        passwordField.placeholder = "密码"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.addTarget(self, action: #selector(textFieldsChanged), for: .editingChanged)

        contentView.addSubview(identifierField)
        contentView.addSubview(passwordField)

        NSLayoutConstraint.activate([
            identifierField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            identifierField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            identifierField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            identifierField.heightAnchor.constraint(equalToConstant: 48),

            passwordField.topAnchor.constraint(equalTo: identifierField.bottomAnchor, constant: 12),
            passwordField.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func setupRememberPassword() {
        rememberSwitch.translatesAutoresizingMaskIntoConstraints = false
        rememberSwitch.onTintColor = .systemOrange
        rememberSwitch.addTarget(self, action: #selector(rememberChanged), for: .valueChanged)

        rememberLabel.translatesAutoresizingMaskIntoConstraints = false
        rememberLabel.text = "记住账号密码"
        rememberLabel.font = .systemFont(ofSize: 15)
        rememberLabel.textColor = .secondaryLabel
        rememberLabel.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(rememberLabelTapped))
        rememberLabel.addGestureRecognizer(tap)

        contentView.addSubview(rememberSwitch)
        contentView.addSubview(rememberLabel)

        NSLayoutConstraint.activate([
            rememberSwitch.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 12),
            rememberSwitch.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),

            rememberLabel.centerYAnchor.constraint(equalTo: rememberSwitch.centerYAnchor),
            rememberLabel.leadingAnchor.constraint(equalTo: rememberSwitch.trailingAnchor, constant: 8),
        ])
    }

    private func setupLoginButton() {
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.title = "登录"
        config.cornerStyle = .medium
        loginButton.configuration = config
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        loginButton.isEnabled = false

        contentView.addSubview(loginButton)

        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: rememberSwitch.bottomAnchor, constant: 20),
            loginButton.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            loginButton.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func setupForgotPassword() {
        forgotPasswordButton.translatesAutoresizingMaskIntoConstraints = false
        forgotPasswordButton.setTitle("忘记密码?", for: .normal)
        forgotPasswordButton.titleLabel?.font = .systemFont(ofSize: 14)
        forgotPasswordButton.setTitleColor(.secondaryLabel, for: .normal)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)

        contentView.addSubview(forgotPasswordButton)

        NSLayoutConstraint.activate([
            forgotPasswordButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 12),
            forgotPasswordButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
    }

    private func setupOtherMethods() {
        dividerLabel.translatesAutoresizingMaskIntoConstraints = false
        dividerLabel.text = "── 其他方式 ──"
        dividerLabel.font = .systemFont(ofSize: 13)
        dividerLabel.textColor = .tertiaryLabel
        dividerLabel.textAlignment = .center

        otherMethodsButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.bordered()
        config.title = "其他方式登录 (OAuth / Passkey)"
        config.image = UIImage(systemName: "globe")
        config.imagePadding = 8
        config.cornerStyle = .medium
        otherMethodsButton.configuration = config
        otherMethodsButton.addTarget(self, action: #selector(otherMethodsTapped), for: .touchUpInside)

        contentView.addSubview(dividerLabel)
        contentView.addSubview(otherMethodsButton)

        NSLayoutConstraint.activate([
            dividerLabel.topAnchor.constraint(equalTo: forgotPasswordButton.bottomAnchor, constant: 20),
            dividerLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            otherMethodsButton.topAnchor.constraint(equalTo: dividerLabel.bottomAnchor, constant: 12),
            otherMethodsButton.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            otherMethodsButton.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            otherMethodsButton.heightAnchor.constraint(equalToConstant: 44),
            otherMethodsButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
        ])
    }

    private func setupErrorBanner() {
        errorBannerLabel.translatesAutoresizingMaskIntoConstraints = false
        errorBannerLabel.font = .systemFont(ofSize: 14)
        errorBannerLabel.textColor = .systemRed
        errorBannerLabel.textAlignment = .center
        errorBannerLabel.numberOfLines = 0
        errorBannerLabel.isHidden = true

        contentView.addSubview(errorBannerLabel)

        NSLayoutConstraint.activate([
            errorBannerLabel.topAnchor.constraint(equalTo: otherMethodsButton.bottomAnchor, constant: 12),
            errorBannerLabel.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            errorBannerLabel.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            errorBannerLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    private func setupActivityIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Credential Auto-fill

    private func applySavedCredentialIfNeeded() {
        Task { @MainActor in
            let credential = viewModel.savedLoginCredential
            guard let credential else { return }
            identifierField.text = credential.username
            passwordField.text = credential.password
            rememberSwitch.isOn = true
            updateLoginButtonState()
        }
    }

    // MARK: - Actions

    @objc private func textFieldsChanged() {
        updateLoginButtonState()
        hideErrorBanner()
    }

    @objc private func rememberChanged() {
        // Toggle handled by UISwitch
    }

    @objc private func rememberLabelTapped() {
        rememberSwitch.setOn(!rememberSwitch.isOn, animated: true)
    }

    @objc private func loginTapped() {
        guard let identifier = identifierField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let password = passwordField.text,
              !identifier.isEmpty, !password.isEmpty else { return }

        pendingIdentifier = identifier
        pendingPassword = password
        pendingRememberCredential = rememberSwitch.isOn
        hideErrorBanner()
        setLoginLoading(true)

        Task { await performLogin() }
    }

    @objc private func forgotPasswordTapped() {
        // Phase 2: present FireWebViewBrowserViewController with /password-reset
        showComingSoon()
    }

    @objc private func otherMethodsTapped() {
        // Phase 2: present FireWebViewBrowserViewController with /login
        showComingSoon()
    }

    // MARK: - Login Flow

    private func performLogin() async {
        // Step 1: Ensure Cloudflare clearance
        let cfOK = await viewModel.ensureCloudflareClearance()
        guard cfOK else {
            await MainActor.run {
                setLoginLoading(false)
                showErrorBanner("网络验证失败，请重试")
            }
            return
        }

        // Step 2: Get login coordinator for the dialog
        let loginCoordinator: FireWebViewLoginCoordinator
        do {
            loginCoordinator = try await viewModel.loginCoordinatorForDialog()
        } catch {
            await MainActor.run {
                setLoginLoading(false)
                showErrorBanner("网络准备失败，请重试")
            }
            return
        }

        // Step 3: Present captcha dialog
        await MainActor.run {
            presentCaptchaDialog(loginCoordinator: loginCoordinator)
        }
    }

    @MainActor
    private func presentCaptchaDialog(loginCoordinator: FireWebViewLoginCoordinator) {
        let dialog = FireCaptchaLoginDialogController(
            identifier: pendingIdentifier,
            password: pendingPassword,
            loginCoordinator: loginCoordinator,
            onResult: { [weak self] result in
                self?.handleDialogResult(result)
            },
            onCancel: { [weak self] in
                self?.setLoginLoading(false)
                self?.captchaDialog = nil
            }
        )

        // Wire up the classifier closure
        dialog.classifyResult = { [weak self] phase, status, body in
            guard let self else { return }
            Task {
                do {
                    let decision = try await self.viewModel.classifyLoginResult(
                        phase: phase,
                        status: status,
                        body: body
                    )
                    await MainActor.run {
                        dialog.dispatchResult(self.dialogResult(from: decision))
                    }
                } catch {
                    await MainActor.run {
                        dialog.dispatchResult(.failure(LoginFailureState(
                            kind: .unknown,
                            message: error.localizedDescription,
                            sentToEmail: nil,
                            currentEmail: nil
                        )))
                    }
                }
            }
        }

        captchaDialog = dialog
        present(dialog, animated: true)
    }

    private func dialogResult(from decision: WebViewLoginDecisionState) -> FireCaptchaDialogResult {
        switch decision {
        case .success:
            return .success
        case .needSecondFactor(let requirement):
            return .needSecondFactor(requirement)
        case .retryCloudflare:
            return .retryCloudflare
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func handleDialogResult(_ result: FireCaptchaDialogResult) {
        switch result {
        case .success:
            completeLoginFromDialog()

        case .needSecondFactor(let requirement):
            if !hasShownSecondFactor || requirement.message != nil {
                showSecondFactorPrompt(requirement: requirement)
            }

        case .retryCloudflare:
            recoverCloudflare()

        case .failure(let failure):
            DispatchQueue.main.async { [weak self] in
                self?.setLoginLoading(false)
                self?.dismissCaptchaDialog()
                self?.showErrorBanner(failure.message ?? "登录失败")
                if failure.kind == .invalidCredentials {
                    self?.passwordField.text = nil
                    self?.updateLoginButtonState()
                }
            }
        }
    }

    private func completeLoginFromDialog() {
        guard let dialog = captchaDialog else { return }
        let webView = dialog.webView
        let identifier = pendingIdentifier
        let password = pendingPassword
        let remember = pendingRememberCredential

        Task { @MainActor in
            viewModel.completeMinimalLogin(
                from: webView,
                identifier: identifier,
                password: password,
                rememberCredential: remember
            )
            // Success sets authPresentationState(nil) → coordinator dismisses everything.
            // Errors are surfaced by observeLoginErrorsAndSyncingState().
        }
    }

    private func showSecondFactorPrompt(requirement: SecondFactorRequirementState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasShownSecondFactor = true

            let alert = UIAlertController(
                title: "两步验证",
                message: requirement.message ?? "请输入验证器中的 6 位代码",
                preferredStyle: .alert
            )
            alert.addTextField { field in
                field.placeholder = "6 位验证码"
                field.keyboardType = .numberPad
                field.textContentType = .oneTimeCode
            }
            alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
                guard let code = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !code.isEmpty else { return }
                self?.captchaDialog?.retryWithSecondFactor(code)
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
                self?.setLoginLoading(false)
                self?.dismissCaptchaDialog()
            })
            self.present(alert, animated: true)
        }
    }

    private func recoverCloudflare() {
        guard !cfRetryUsed else {
            DispatchQueue.main.async { [weak self] in
                self?.setLoginLoading(false)
                self?.dismissCaptchaDialog()
                self?.showErrorBanner("网络验证失败，请稍后重试")
            }
            return
        }
        cfRetryUsed = true

        Task {
            // Use existing recoverLoginCloudflareChallenge logic via ViewModel
            await MainActor.run {
                // ViewModel.recoverLoginCloudflareChallenge re-primes and retries
                // The dialog's WebView will re-run __fireLogin after CF recovery
                // This needs the dialog to stay alive and re-prime
                // For now, dismiss and re-present after CF recovery
                // TODO: implement CF retry within the same dialog
            }
        }
    }

    // MARK: - Helpers

    private func updateLoginButtonState() {
        let hasId = !(identifierField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasPwd = !(passwordField.text?.isEmpty ?? true)
        loginButton.isEnabled = hasId && hasPwd
    }

    private func setLoginLoading(_ loading: Bool) {
        if loading {
            activityIndicator.startAnimating()
            loginButton.isEnabled = false
            view.isUserInteractionEnabled = false
        } else {
            activityIndicator.stopAnimating()
            updateLoginButtonState()
            view.isUserInteractionEnabled = true
        }
    }

    private func showErrorBanner(_ message: String) {
        errorBannerLabel.text = message
        errorBannerLabel.isHidden = false
    }

    private func hideErrorBanner() {
        errorBannerLabel.isHidden = true
    }

    private func dismissCaptchaDialog() {
        captchaDialog?.dismiss(animated: true) { [weak self] in
            self?.captchaDialog = nil
        }
    }

    private func showComingSoon() {
        let alert = UIAlertController(title: "即将支持", message: "此功能将在后续版本中推出，敬请期待。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        present(alert, animated: true)
    }
}
```

Note: The `dispatchResult` method on `FireCaptchaLoginDialogController` needs to be added — it's the bridge between the `classifyResult` closure and `reportResult`. Add it to the dialog:

In `FireCaptchaLoginDialogController.swift`, add:
```swift
/// Called by the presenting VC after classifying the JS result.
func dispatchResult(_ result: FireCaptchaDialogResult) {
    reportResult(result)
}
```

- [ ] **Step 2: Add `dispatchResult` to dialog**

Add to `FireCaptchaLoginDialogController`:
```swift
func dispatchResult(_ result: FireCaptchaDialogResult) {
    reportResult(result)
}
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodegen generate --spec native/ios-app/project.yml && xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

Expected: Build should succeed except for `FireRootCoordinator` still referencing old VC and `FireLoginWebView.swift` referencing old `completeMinimalLogin` signature.

- [ ] **Step 4: Commit**

```bash
git add native/ios-app/App/Views/Other/FireLoginViewController.swift native/ios-app/App/Views/Other/FireCaptchaLoginDialogController.swift
git commit -m "feat(login): add FireLoginViewController with native form layout"
```

---

### Task 4: Switch Root Coordinator + Delete Old VC

**Files:**
- Modify: `native/ios-app/App/Core/FireRootCoordinator.swift`
- Delete: `native/ios-app/App/Views/Other/FireLoginWebView.swift`

**Context:** The coordinator currently creates `FireLoginWebViewController` inside `syncAuthPresentation(_:)`. This task is the build cutover that removes the old VC after the ViewModel signature changes. Task 5 must follow before the branch is considered mergeable/releasable, because same-dialog CF retry is part of the complete native login behavior.

- [ ] **Step 1: Replace VC construction in coordinator**

In `FireRootCoordinator.swift`, find the `syncAuthPresentation` method (around line 357-368). Replace the construction of `FireLoginWebViewController` with `FireLoginViewController`:

```swift
let controller = FireLoginViewController(viewModel: viewModel)
let navigationController = UINavigationController(rootViewController: controller)
navigationController.modalPresentationStyle = .fullScreen
presentationAnchor()?.present(navigationController, animated: true)
authController = navigationController
```

Find the exact old code that constructs `FireLoginWebViewController` and replace it. The old code likely looks like:
```swift
let controller = FireLoginWebViewController(
    viewModel: viewModel,
    presentationState: state
)
```

- [ ] **Step 2: Delete old login VC**

```bash
git rm native/ios-app/App/Views/Other/FireLoginWebView.swift
```

- [ ] **Step 3: Verify build**

Run: `xcodegen generate --spec native/ios-app/project.yml && xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30`

Expected: Build succeeds. If there are references to `FireLoginWebViewController` elsewhere, find and update them.

- [ ] **Step 4: Commit**

```bash
git add -A native/ios-app/
git commit -m "feat(login): switch to FireLoginViewController, delete FireLoginWebView

- Root coordinator presents FireLoginViewController
- FireLoginWebView.swift removed (816 lines → 0)
- Login flow: native form → on-demand CF → captcha dialog → finalize"
```

Gate: do not merge or ship at this point. Continue immediately with Task 5 so `.retryCloudflare` reuses the same live dialog/WebView instead of failing back to a stale outer login flow.

---

### Task 5: Fix CF Retry Within Dialog

**Files:**
- Modify: `native/ios-app/App/Views/Other/FireLoginViewController.swift`

**Context:** The `recoverCloudflare()` method in Task 3 has a TODO for CF retry within the same dialog. The knowledge base (`discourse-webview-login-guide.md:252-264`) specifies: CF verification → wait for cookie propagation → extract cookies → write to Rust trusted → re-prime the same live WebView → re-run `__fireLogin` with the same arguments that failed during the csrf phase.

- [ ] **Step 1: Implement CF retry within dialog**

Replace the `recoverCloudflare()` method in `FireLoginViewController`:

```swift
    private func recoverCloudflare() {
        guard !cfRetryUsed else {
            DispatchQueue.main.async { [weak self] in
                self?.setLoginLoading(false)
                self?.dismissCaptchaDialog()
                self?.showErrorBanner("网络验证失败，请稍后重试")
            }
            return
        }
        cfRetryUsed = true

        Task {
            // Use existing recoverLoginCloudflareChallenge(in:) which always
            // forces CF challenge + 1.5s propagation wait + re-prime.
            // This is NOT the same as ensureCloudflareClearance() which
            // short-circuits when session readiness already has CF clearance — but .retryCloudflare
            // means the current clearance was rejected by /session/csrf.
            guard let dialog = self.captchaDialog else { return }
            do {
                try await viewModel.recoverLoginCloudflareChallenge(in: dialog.webView)
            } catch {
                await MainActor.run {
                    self.setLoginLoading(false)
                    self.dismissCaptchaDialog()
                    self.showErrorBanner("网络验证失败，请重试")
                }
                return
            }

            // Re-run __fireLogin with the same arguments that failed during csrf.
            await MainActor.run {
                dialog.retryAfterCloudflareRecovery()
            }
        }
    }
```

- [ ] **Step 2: Add `retryAfterCloudflareRecovery` to dialog**

In `FireCaptchaLoginDialogController.swift`, add:

```swift
/// Re-primes and re-runs __fireLogin after CF recovery.
/// Reuses the same arguments because csrf phase fails before hCaptcha create/session submit.
func retryAfterCloudflareRecovery() {
    guard lastLoginHcaptchaToken != nil || lastLoginSecondFactorToken != nil else {
        statusLabel.text = "请重新尝试登录"
        statusLabel.textColor = .secondaryLabel
        hasReportedResult = false
        return
    }
    hasReportedResult = false
    statusLabel.text = "正在重试登录…"
    statusLabel.textColor = .secondaryLabel
    activityIndicator.startAnimating()
    let invocation = FireLoginScripts.fireLoginInvocation(
        identifier: identifier,
        password: password,
        hcaptchaToken: lastLoginHcaptchaToken,
        secondFactorToken: lastLoginSecondFactorToken
    )
    webView.evaluateJavaScript(invocation) { [weak self] _, error in
        if let error {
            self?.reportResult(.failure(LoginFailureState(
                kind: .unknown,
                message: error.localizedDescription,
                sentToEmail: nil,
                currentEmail: nil
            )))
        }
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodegen generate --spec native/ios-app/project.yml && xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add native/ios-app/App/Views/Other/FireLoginViewController.swift native/ios-app/App/Views/Other/FireCaptchaLoginDialogController.swift
git commit -m "feat(login): implement CF retry within captcha dialog

Re-prime live WebView and reuse the failed csrf attempt args after CF recovery
per discourse-webview-login-guide.md:252-264."
```

---

## Phase 2: Full WebView Fallback (Social Login + Forgot Password)

### Task 6: Create FireWebViewBrowserViewController

**Files:**
- Create: `native/ios-app/App/Views/Other/FireWebViewBrowserViewController.swift`

**Context:** A simple full-screen WKWebView browser VC for loading `linux.do/login` or `linux.do/password-reset`. It uses the shared browser profile so preloaded bootstrap capture and fingerprint scripts stay installed. It monitors auth cookies, probes full login sync readiness, and only then triggers the existing `completeLogin(from:)` finalizer.

- [ ] **Step 1: Create the browser VC**

Create `native/ios-app/App/Views/Other/FireWebViewBrowserViewController.swift`:

```swift
import Combine
import UIKit
import WebKit

/// Full-screen WebView browser for login fallback paths (OAuth, Passkey,
/// forgot password). Loads linux.do pages and detects login success via
/// cookie monitoring.
final class FireWebViewBrowserViewController: UIViewController {

    // MARK: - Properties

    private let initialURL: URL
    private let viewModel: FireAppViewModel
    private var webView: WKWebView!
    private var navigationBar: UINavigationBar!
    private var progressView: UIProgressView!
    private var hasFinalizedLogin = false
    private var cookiePollTimer: Timer?
    private let scriptMessageProxy = FireBrowserScriptMessageProxy()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(url: URL, viewModel: FireAppViewModel) {
        self.initialURL = url
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupWebView()
        setupProgressView()
        observeViewModelErrors()
        loadURL()
        startCookiePolling()
    }

    deinit {
        cookiePollTimer?.invalidate()
        webView?.removeObserver(self, forKeyPath: "estimatedProgress")
        [
            FireLoginScripts.loginCredentialsMessageName,
            FireLoginScripts.fingerprintDoneMessageName,
        ].forEach { name in
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
        webView?.stopLoading()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        navigationBar = UINavigationBar()
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        let navItem = UINavigationItem(title: initialURL.host ?? "")
        navItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        navItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            primaryAction: UIAction { [weak self] _ in
                self?.webView?.reload()
            }
        )
        navigationBar.items = [navItem]
        view.addSubview(navigationBar)

        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupWebView() {
        scriptMessageProxy.onMessage = { [weak self] message in
            self?.handleScriptMessage(message)
        }
        let configuration = FireWebViewBrowserProfile.makeLoginConfiguration(
            credential: viewModel.savedLoginCredential,
            messageHandler: scriptMessageProxy
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        FireWebViewBrowserProfile.configure(
            webView,
            preferredUserAgent: viewModel.session.browserUserAgent
        )
        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func observeViewModelErrors() {
        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .sink { [weak self] message in
                guard let self, self.hasFinalizedLogin else { return }
                self.hasFinalizedLogin = false
                self.startCookiePolling()
                self.showErrorAlert(message)
            }
            .store(in: &cancellables)
    }

    private func setupProgressView() {
        progressView = UIProgressView(progressViewStyle: .bar)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tintColor = .systemOrange
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: webView.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func loadURL() {
        // Prime cookies from Rust before loading. The WebView configuration
        // already installed preloadedDataCapture, credential autofill, and
        // fingerprint intercept scripts through makeLoginConfiguration.
        Task {
            do {
                let loginCoordinator = try await viewModel.loginCoordinatorForDialog()
                try await loginCoordinator.primeCookies(
                    into: webView,
                    targetURL: URL(string: "https://linux.do/")
                )
            } catch {
                // Non-fatal: continue without priming
            }
            await MainActor.run {
                self.webView.load(URLRequest(url: self.initialURL))
            }
        }
    }

    private func startCookiePolling() {
        // Poll for _t cookie (auth token) every 2 seconds
        cookiePollTimer?.invalidate()
        cookiePollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForAuthToken()
        }
    }

    private func checkForAuthToken() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.hasFinalizedLogin else { return }
                let hasAuth = cookies.contains { $0.name == "_t" && !$0.value.isEmpty }
                guard hasAuth else { return }

                do {
                    let readiness = try await self.viewModel.probeLoginSyncReadiness(from: self.webView)
                    guard readiness.isReady else { return }
                } catch {
                    return
                }

                self.hasFinalizedLogin = true
                self.cookiePollTimer?.invalidate()
                // Use completeLogin(from:) for full WebView path — it reads
                // username/csrf from page meta/preloaded data, not from params.
                self.viewModel.completeLogin(from: self.webView)
            }
        }
    }

    private func handleScriptMessage(_ message: WKScriptMessage) {
        switch message.name {
        case FireLoginScripts.fingerprintDoneMessageName:
            viewModel.recordLoginFingerprintDone()
        case FireLoginScripts.loginCredentialsMessageName:
            // The native login form owns credential persistence. For fallback
            // pages this message is only used to keep preloaded capture active.
            break
        default:
            break
        }
    }

    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "登录同步失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重试", style: .default))
        present(alert, animated: true)
    }

    // MARK: - KVO

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "estimatedProgress" {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.progressView.progress = Float(self.webView.estimatedProgress)
                self.progressView.isHidden = self.webView.estimatedProgress >= 1.0
            }
        }
    }
}

private final class FireBrowserScriptMessageProxy: NSObject, WKScriptMessageHandler {
    var onMessage: ((WKScriptMessage) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        onMessage?(message)
    }
}
```

Note: Cookie monitoring uses a 2-second polling timer against `WKWebsiteDataStore.default().httpCookieStore.getAllCookies`. `_t` only indicates an auth cookie exists; finalization must also wait for `probeLoginSyncReadiness(from:)` because the Rust finalizer requires auth cookies plus captured username/bootstrap data from the preloaded scripts. Use `completeLogin(from:)` for this full WebView path; do not call `completeMinimalLogin` with empty credentials.

- [ ] **Step 2: Wire up forgot-password and other-methods buttons**

In `FireLoginViewController.swift`, replace the `showComingSoon()` calls:

```swift
@objc private func forgotPasswordTapped() {
    let url = URL(string: "https://linux.do/password-reset")!
    presentWebViewBrowser(url: url)
}

@objc private func otherMethodsTapped() {
    let url = URL(string: "https://linux.do/login")!
    presentWebViewBrowser(url: url)
}

private func presentWebViewBrowser(url: URL) {
    let browser = FireWebViewBrowserViewController(url: url, viewModel: viewModel)
    browser.modalPresentationStyle = .fullScreen
    present(browser, animated: true)
}

private func showComingSoon() {
    // Remove this method — no longer needed
}
```

Remove the `showComingSoon()` method body and the two call sites that used it.

- [ ] **Step 3: Verify build**

Run: `xcodegen generate --spec native/ios-app/project.yml && xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add native/ios-app/App/Views/Other/FireWebViewBrowserViewController.swift native/ios-app/App/Views/Other/FireLoginViewController.swift
git commit -m "feat(login): add WebView browser fallback for OAuth/forgot-password"
```

---

## Phase 3: Error Handling Polish

### Task 7: Inline Error Banner Component

**Files:**
- Modify: `native/ios-app/App/Views/Other/FireLoginViewController.swift`

**Context:** Currently errors are shown via a simple hidden label. Improve to a proper auto-dismissing banner with animation. Also handle repeated `needSecondFactor` messages in the 2FA alert.

- [ ] **Step 1: Replace error label with animated banner**

Replace `errorBannerLabel` with a container view that slides in/out:

```swift
private let errorBannerContainer = UIView()
private let errorBannerImageView = UIImageView()
private let errorBannerLabel = UILabel()

private func setupErrorBanner() {
    errorBannerContainer.translatesAutoresizingMaskIntoConstraints = false
    errorBannerContainer.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
    errorBannerContainer.layer.cornerRadius = 8
    errorBannerContainer.isHidden = true
    errorBannerContainer.alpha = 0

    errorBannerImageView.translatesAutoresizingMaskIntoConstraints = false
    errorBannerImageView.image = UIImage(systemName: "exclamationmark.triangle.fill")
    errorBannerImageView.tintColor = .systemRed

    errorBannerLabel.translatesAutoresizingMaskIntoConstraints = false
    errorBannerLabel.font = .systemFont(ofSize: 14)
    errorBannerLabel.textColor = .systemRed
    errorBannerLabel.numberOfLines = 0

    errorBannerContainer.addSubview(errorBannerImageView)
    errorBannerContainer.addSubview(errorBannerLabel)
    view.addSubview(errorBannerContainer)

    NSLayoutConstraint.activate([
        errorBannerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        errorBannerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
        errorBannerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

        errorBannerImageView.topAnchor.constraint(equalTo: errorBannerContainer.topAnchor, constant: 12),
        errorBannerImageView.leadingAnchor.constraint(equalTo: errorBannerContainer.leadingAnchor, constant: 12),
        errorBannerImageView.widthAnchor.constraint(equalToConstant: 20),
        errorBannerImageView.heightAnchor.constraint(equalToConstant: 20),
        errorBannerImageView.bottomAnchor.constraint(lessThanOrEqualTo: errorBannerContainer.bottomAnchor, constant: -12),

        errorBannerLabel.topAnchor.constraint(equalTo: errorBannerContainer.topAnchor, constant: 12),
        errorBannerLabel.leadingAnchor.constraint(equalTo: errorBannerImageView.trailingAnchor, constant: 8),
        errorBannerLabel.trailingAnchor.constraint(equalTo: errorBannerContainer.trailingAnchor, constant: -12),
        errorBannerLabel.bottomAnchor.constraint(equalTo: errorBannerContainer.bottomAnchor, constant: -12),
    ])
}

private func showErrorBanner(_ message: String) {
    errorBannerLabel.text = message
    errorBannerContainer.isHidden = false
    UIView.animate(withDuration: 0.25) {
        self.errorBannerContainer.alpha = 1
    }
    // Auto-dismiss after 4 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
        self?.hideErrorBanner()
    }
}

private func hideErrorBanner() {
    guard !errorBannerContainer.isHidden else { return }
    UIView.animate(withDuration: 0.25, animations: {
        self.errorBannerContainer.alpha = 0
    }) { _ in
        self.errorBannerContainer.isHidden = true
    }
}
```

- [ ] **Step 2: Handle repeated needSecondFactor with error message**

Update `showSecondFactorPrompt` to show the server message as the alert body when retrying:

```swift
private func showSecondFactorPrompt(requirement: SecondFactorRequirementState) {
    DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        let isFirstAttempt = !self.hasShownSecondFactor
        self.hasShownSecondFactor = true

        let title = isFirstAttempt ? "两步验证" : "验证码错误"
        let message = requirement.message ?? "请输入验证器中的 6 位代码"

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "6 位验证码"
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
        }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let code = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !code.isEmpty else { return }
            self?.captchaDialog?.retryWithSecondFactor(code)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.setLoginLoading(false)
            self?.dismissCaptchaDialog()
        })
        self.present(alert, animated: true)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodegen generate --spec native/ios-app/project.yml && xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add native/ios-app/App/Views/Other/FireLoginViewController.swift
git commit -m "polish(login): animated error banner + 2FA retry messaging"
```

---

## Post-Implementation Verification

### Task 8: Manual Flow Verification

- [ ] **Step 1: Verify cold-start login flow**

1. Clear app data / sign out
2. Launch app → should land on onboarding
3. Tap "登录 LinuxDo"
4. Verify: login page shows logo, inputs, remember checkbox, login button, forgot password, other methods — **no hCaptcha visible, no network activity**
5. Type credentials, tap login
6. Verify: CF challenge appears if needed, then captcha dialog appears with hCaptcha
7. Complete hCaptcha → verify login succeeds → app enters main interface

- [ ] **Step 2: Verify remember-password**

1. Log out
2. Open login page → verify saved credentials auto-filled, checkbox on
3. Uncheck "记住密码", log in
4. Log out again
5. Open login → verify fields are **empty** (old saved credentials were cleared)

- [ ] **Step 3: Verify 2FA flow**

1. Log in with a 2FA-enabled account
2. Verify 2FA prompt appears after hCaptcha
3. Enter wrong code → verify "验证码错误" message with server error
4. Enter correct code → verify login succeeds

- [ ] **Step 4: Verify WebView fallback**

1. Tap "忘记密码?" → verify WebView loads `/password-reset`
2. Close, tap "其他方式登录" → verify WebView loads `/login`

- [ ] **Step 5: Verify error states**

1. Enter wrong password → verify inline error banner (not UIAlertController)
2. Verify banner auto-dismisses after 4 seconds

- [ ] **Step 6: Commit final state**

```bash
git add -A
git commit -m "feat(login): native login page redesign complete

- FireLoginViewController: pure-native UIKit login page
- FireCaptchaLoginDialogController: hCaptcha + login request dialog
- Login flow: credentials first → CF on-demand → hCaptcha → finalize
- Remember-password checkbox threaded to save API
- WebView fallback for OAuth/forgot-password
- Animated error banner"
```

---

## Spec Coverage Checklist

| Spec Requirement | Task |
|-----------------|------|
| Native UIKit login page (logo, inputs, checkbox, buttons) | Task 3 |
| hCaptcha dialog VC with live WebView | Task 1 |
| CF on-demand trigger (not page-open) | Task 2, Task 3 |
| `rememberCredential` param threaded to finalize | Task 2 |
| VC owns dialog present/dismiss, ViewModel async capabilities | Task 2, Task 3 |
| Live WebView handoff for cookie extraction | Task 1, Task 3 |
| Delete FireLoginWebView.swift | Task 4 |
| Forgot password → WebView /password-reset | Task 6 |
| Other login methods → WebView /login | Task 6 |
| Error states per WebViewLoginDecisionState | Task 3, Task 7 |
| 2FA retry in same live WebView | Task 1, Task 3 |
| CF retry within dialog (reuse failed csrf attempt args) | Task 5 |
| Animated inline error banner | Task 7 |
