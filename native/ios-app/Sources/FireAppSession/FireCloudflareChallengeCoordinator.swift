import Foundation
import UIKit
import WebKit

final class FireCloudflareChallengeRuntimeHandler: CloudflareChallengeHandler, @unchecked Sendable {
    private let coordinator: FireCloudflareChallengeCoordinator

    init(sessionStore: FireSessionStore) {
        self.coordinator = FireCloudflareChallengeCoordinator(sessionStore: sessionStore)
    }

    func completeCloudflareChallenge(
        request: CloudflareChallengeRequestState
    ) -> CloudflareChallengeResultState {
        coordinator.completeSynchronously(request: request)
    }
}

final class FireCloudflareChallengeCoordinator: NSObject, @unchecked Sendable {
    private let sessionStore: FireSessionStore

    init(sessionStore: FireSessionStore) {
        self.sessionStore = sessionStore
    }

    nonisolated func completeSynchronously(
        request: CloudflareChallengeRequestState
    ) -> CloudflareChallengeResultState {
        if Thread.isMainThread {
            return CloudflareChallengeResultState(
                completed: false,
                userCancelled: false,
                cookies: [],
                browserUserAgent: nil
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        let state = LockedChallengeResultState()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                state.set(
                    CloudflareChallengeResultState(
                        completed: false,
                        userCancelled: false,
                        cookies: [],
                        browserUserAgent: nil
                    )
                )
                semaphore.signal()
                return
            }

            Task { @MainActor in
                let result = await self.complete(request: request)
                state.set(result)
                semaphore.signal()
            }
        }
        semaphore.wait()
        return state.get()
    }

    @MainActor
    func completeManualVerification(originURL: String? = "https://linux.do/") async -> CloudflareChallengeResultState {
        let epoch = (try? await sessionStore.currentSessionEpoch()) ?? 0
        return await complete(
            request: CloudflareChallengeRequestState(
                operation: "login.csrf",
                requestUrl: "https://linux.do/session/csrf",
                originUrl: originURL,
                isForeground: true,
                sessionEpoch: epoch
            )
        )
    }

    @MainActor
    private func complete(
        request: CloudflareChallengeRequestState
    ) async -> CloudflareChallengeResultState {
        guard request.isForeground else {
            return CloudflareChallengeResultState(
                completed: false,
                userCancelled: false,
                cookies: [],
                browserUserAgent: nil
            )
        }
        guard let presenter = topPresenter() else {
            return CloudflareChallengeResultState(
                completed: false,
                userCancelled: false,
                cookies: [],
                browserUserAgent: nil
            )
        }

        let baseline = await currentCookieSnapshot()
        let snapshot = try? await sessionStore.snapshot()
        let challengeURL = challengeURL(
            request.originUrl,
            fallbackBaseURL: snapshot?.bootstrap.baseUrl
        )
        let controller = FireCloudflareChallengeViewController(
            url: challengeURL,
            preferredUserAgent: snapshot?.browserUserAgent,
            baselineSnapshot: baseline
        )
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        presenter.present(navigationController, animated: true)
        let outcome = await controller.awaitOutcome()
        switch outcome {
        case .cancelled:
            return CloudflareChallengeResultState(
                completed: false,
                userCancelled: true,
                cookies: [],
                browserUserAgent: nil
            )
        case let .completed(browserUserAgent):
            let loginCoordinator = FireWebViewLoginCoordinator(sessionStore: sessionStore)
            let cookies = (try? await loginCoordinator.platformCookiesForSessionResync()) ?? []
            return CloudflareChallengeResultState(
                completed: true,
                userCancelled: false,
                cookies: cookies,
                browserUserAgent: browserUserAgent
            )
        }
    }

    @MainActor
    private func challengeURL(_ originURL: String?, fallbackBaseURL: String?) -> URL {
        if let originURL, let url = URL(string: originURL) {
            return url
        }
        if let fallbackBaseURL, let baseURL = URL(string: fallbackBaseURL) {
            return baseURL.appending(path: "challenge")
        }
        return URL(string: "https://linux.do/challenge")!
    }

    @MainActor
    private func currentCookieSnapshot() async -> FireCloudflareRecoveryCookieSnapshot {
        let cookies = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        return challengeCookieSnapshot(from: cookies)
    }

    @MainActor
    private func challengeCookieSnapshot(
        from cookies: [HTTPCookie]
    ) -> FireCloudflareRecoveryCookieSnapshot {
        let relevant = cookies.filter {
            $0.domain.range(of: "linux.do", options: .caseInsensitive) != nil
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let authValues = relevant
            .filter { $0.name == "_t" || $0.name == "_forum_session" }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
        let cfValue = relevant.first(where: { $0.name == "cf_clearance" })?.value
        return FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: authValues.contains(where: { $0.hasPrefix("_t=") })
                && authValues.contains(where: { $0.hasPrefix("_forum_session=") }),
            authFingerprint: authValues.joined(separator: ";"),
            cfClearanceFingerprint: cfValue
        )
    }

    @MainActor
    private func topPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter {
                $0.activationState == .foregroundActive
                    || $0.activationState == .foregroundInactive
            }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        return topPresentedController(from: window?.rootViewController)
    }

    @MainActor
    private func topPresentedController(from root: UIViewController?) -> UIViewController? {
        if let navigation = root as? UINavigationController {
            return topPresentedController(from: navigation.visibleViewController)
        }
        if let tabBar = root as? UITabBarController {
            return topPresentedController(from: tabBar.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topPresentedController(from: presented)
        }
        return root
    }
}

private final class LockedChallengeResultState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = CloudflareChallengeResultState(
        completed: false,
        userCancelled: false,
        cookies: [],
        browserUserAgent: nil
    )

    func set(_ value: CloudflareChallengeResultState) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func get() -> CloudflareChallengeResultState {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class FireCloudflareChallengeViewController: UIViewController, WKNavigationDelegate,
    WKUIDelegate, WKHTTPCookieStoreObserver
{
    enum Outcome {
        case completed(browserUserAgent: String?)
        case cancelled
    }

    private let url: URL
    private let preferredUserAgent: String?
    private let baselineSnapshot: FireCloudflareRecoveryCookieSnapshot
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var finished = false

    init(
        url: URL,
        preferredUserAgent: String?,
        baselineSnapshot: FireCloudflareRecoveryCookieSnapshot
    ) {
        self.url = url
        self.preferredUserAgent = preferredUserAgent
        self.baselineSnapshot = baselineSnapshot
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Cloudflare 验证"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        let configuration = FireWebViewBrowserProfile.makeConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        FireWebViewBrowserProfile.configure(webView, preferredUserAgent: preferredUserAgent)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        configuration.websiteDataStore.httpCookieStore.add(self)
        self.webView = webView
        webView.load(URLRequest(url: url))
    }

    func awaitOutcome() async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    @objc
    private func closeTapped() {
        finish(.cancelled)
    }

    private func finish(_ outcome: Outcome) {
        guard !finished else { return }
        finished = true
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        let completion = continuation
        continuation = nil
        (navigationController ?? self).dismiss(animated: true) {
            completion?.resume(returning: outcome)
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            await evaluateCompletion()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            await evaluateCompletion()
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }
        webView.load(navigationAction.request)
        return nil
    }

    private func evaluateCompletion() async {
        guard let webView, !finished else { return }

        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        let snapshot = challengeCookieSnapshot(from: cookies)
        guard snapshot.hasNewCloudflareClearance(comparedTo: baselineSnapshot) else {
            return
        }

        let stillBlocked = (try? await challengeStillPresent(in: webView)) ?? true
        guard !stillBlocked else {
            return
        }
        finish(.completed(browserUserAgent: webView.customUserAgent))
    }

    private func challengeCookieSnapshot(
        from cookies: [HTTPCookie]
    ) -> FireCloudflareRecoveryCookieSnapshot {
        let relevant = cookies.filter {
            $0.domain.range(of: "linux.do", options: .caseInsensitive) != nil
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let authValues = relevant
            .filter { $0.name == "_t" || $0.name == "_forum_session" }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
        let cfValue = relevant.first(where: { $0.name == "cf_clearance" })?.value
        return FireCloudflareRecoveryCookieSnapshot(
            hasAuthCookies: authValues.contains(where: { $0.hasPrefix("_t=") })
                && authValues.contains(where: { $0.hasPrefix("_forum_session=") }),
            authFingerprint: authValues.joined(separator: ";"),
            cfClearanceFingerprint: cfValue
        )
    }

    private func challengeStillPresent(in webView: WKWebView) async throws -> Bool {
        let value = try await webView.evaluateJavaScript(
            """
            (function() {
              try {
                var title = (document.title || '').toLowerCase();
                var html = (document.documentElement && document.documentElement.outerHTML || '')
                  .slice(0, 12000)
                  .toLowerCase();
                return html.indexOf('cf_chl_opt') !== -1 ||
                  (html.indexOf('challenge-platform') !== -1 && html.indexOf('cloudflare') !== -1) ||
                  (title.indexOf('just a moment') !== -1) ||
                  (html.indexOf('just a moment') !== -1 &&
                    (html.indexOf('cloudflare') !== -1 || html.indexOf('cf-challenge') !== -1));
              } catch (error) {
                return true;
              }
            })();
            """
        )
        return value as? Bool ?? true
    }
}
