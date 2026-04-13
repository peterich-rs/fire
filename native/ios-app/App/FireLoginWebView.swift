import SwiftUI
import WebKit

final class FireWebViewBox: ObservableObject {
    weak var webView: WKWebView?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var pageTitle = "LinuxDo Login"
    @Published var currentURL: String?

    func attach(_ webView: WKWebView) {
        self.webView = webView
        syncState(from: webView)
    }

    func syncState(from webView: WKWebView) {
        let nextCanGoBack = webView.canGoBack
        if canGoBack != nextCanGoBack {
            canGoBack = nextCanGoBack
        }

        let nextCanGoForward = webView.canGoForward
        if canGoForward != nextCanGoForward {
            canGoForward = nextCanGoForward
        }

        let nextIsLoading = webView.isLoading
        if isLoading != nextIsLoading {
            isLoading = nextIsLoading
        }

        let nextPageTitle = webView.title ?? "LinuxDo Login"
        if pageTitle != nextPageTitle {
            pageTitle = nextPageTitle
        }

        let nextCurrentURL = webView.url?.host ?? webView.url?.absoluteString
        if currentURL != nextCurrentURL {
            currentURL = nextCurrentURL
        }
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func loadHome() {
        guard let webView, let url = URL(string: "https://linux.do") else {
            return
        }
        webView.load(URLRequest(url: url))
    }
}

public final class FireLoginWebViewProbeBridge: NSObject, WKHTTPCookieStoreObserver {
    private static let cookieProbeDebounceDelay: TimeInterval = 0.35

    private weak var observedWebView: WKWebView?
    private weak var observedCookieStore: WKHTTPCookieStore?
    private var pendingProbeWorkItem: DispatchWorkItem?
    private let onProbeRequested: (WKWebView) -> Void

    public init(onProbeRequested: @escaping (WKWebView) -> Void) {
        self.onProbeRequested = onProbeRequested
    }

    deinit {
        pendingProbeWorkItem?.cancel()
        observedCookieStore?.remove(self)
    }

    public func attach(to webView: WKWebView) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        if observedCookieStore !== cookieStore {
            observedCookieStore?.remove(self)
            cookieStore.add(self)
            observedCookieStore = cookieStore
        }
        observedWebView = webView
    }

    public func detach() {
        pendingProbeWorkItem?.cancel()
        pendingProbeWorkItem = nil
        observedCookieStore?.remove(self)
        observedCookieStore = nil
        observedWebView = nil
    }

    public func requestProbe() {
        requestProbe(after: 0)
    }

    private func requestProbe(after delay: TimeInterval) {
        pendingProbeWorkItem?.cancel()
        guard let observedWebView else {
            return
        }

        let workItem = DispatchWorkItem { [weak self, weak observedWebView] in
            guard self != nil, let observedWebView else {
                return
            }
            self?.pendingProbeWorkItem = nil
            self?.onProbeRequested(observedWebView)
        }
        pendingProbeWorkItem = workItem

        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    public func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        requestProbe(after: Self.cookieProbeDebounceDelay)
    }
}

struct FireLoginWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var webViewBox: FireWebViewBox
    let onNavigationStateChange: (WKWebView) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        webViewBox.attach(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.attach(to: uiView)
        webViewBox.webView = uiView
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
        uiView.navigationDelegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            webViewBox: webViewBox,
            onNavigationStateChange: onNavigationStateChange
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let webViewBox: FireWebViewBox
        private let probeBridge: FireLoginWebViewProbeBridge

        init(
            webViewBox: FireWebViewBox,
            onNavigationStateChange: @escaping (WKWebView) -> Void
        ) {
            self.webViewBox = webViewBox
            self.probeBridge = FireLoginWebViewProbeBridge(onProbeRequested: onNavigationStateChange)
        }

        func attach(to webView: WKWebView) {
            probeBridge.attach(to: webView)
        }

        func detach() {
            probeBridge.detach()
        }

        private func syncBrowserState(from webView: WKWebView) {
            webViewBox.syncState(from: webView)
        }

        private func handleTerminalStateChange(for webView: WKWebView) {
            syncBrowserState(from: webView)
            probeBridge.attach(to: webView)
            probeBridge.requestProbe()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            syncBrowserState(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            syncBrowserState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            handleTerminalStateChange(for: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            handleTerminalStateChange(for: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleTerminalStateChange(for: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            handleTerminalStateChange(for: webView)
        }
    }
}

struct FireAuthScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: FireAppViewModel
    let presentationState: FireAuthPresentationState
    @StateObject private var webViewBox = FireWebViewBox()

    private var title: String {
        switch presentationState {
        case .login:
            return "登录 LinuxDo"
        case .cloudflareRecovery:
            return "完成安全验证"
        }
    }

    private var url: URL {
        switch presentationState {
        case .login:
            return URL(string: "https://linux.do")!
        case let .cloudflareRecovery(context):
            return context.preferredURL
        }
    }

    private var route: String {
        switch presentationState {
        case .login:
            return "auth.login"
        case .cloudflareRecovery:
            return "auth.cloudflare"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if webViewBox.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(FireTheme.accent)
                }

                FireLoginAddressBar(currentURL: webViewBox.currentURL)

                if let errorMessage = viewModel.errorMessage {
                    FireLoginErrorBanner(
                        message: errorMessage,
                        onDismiss: { viewModel.dismissError() }
                    )
                }

                if case let .cloudflareRecovery(context) = presentationState {
                    FireAuthInfoBanner(message: context.message)
                }

                FireLoginWebView(
                    url: url,
                    webViewBox: webViewBox,
                    onNavigationStateChange: { webView in
                        guard case .login = presentationState else {
                            return
                        }
                        viewModel.refreshLoginSyncReadiness(from: webView)
                    }
                )
                .frame(maxHeight: .infinity)
            }
            .background(Color(.systemBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { viewModel.dismissAuthPresentation() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        webViewBox.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                FireAuthBottomBar(
                    viewModel: viewModel,
                    presentationState: presentationState,
                    webViewBox: webViewBox,
                    onLoginSync: {
                        guard let webView = webViewBox.webView else { return }
                        viewModel.completeLogin(from: webView)
                    },
                    onCloudflareRecoveryComplete: {
                        viewModel.completeCloudflareRecovery()
                    }
                )
            }
            .onAppear {
                viewModel.setAPMRoute(route)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let webView = webViewBox.webView else {
                    return
                }
                guard case .login = presentationState else {
                    return
                }
                viewModel.refreshLoginSyncReadiness(from: webView)
            }
            .onDisappear {
                viewModel.restoreTopLevelAPMRoute()
            }
        }
    }
}

private struct FireLoginAddressBar: View {
    let currentURL: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(FireTheme.tertiaryInk)

            Text(currentURL ?? "linux.do")
                .font(.caption)
                .foregroundStyle(FireTheme.subtleInk)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }
}

private struct FireAuthBottomBar: View {
    @ObservedObject var viewModel: FireAppViewModel
    let presentationState: FireAuthPresentationState
    @ObservedObject var webViewBox: FireWebViewBox
    let onLoginSync: () -> Void
    let onCloudflareRecoveryComplete: () -> Void

    private var isRunningAction: Bool {
        switch presentationState {
        case .login:
            return viewModel.isSyncingLoginSession
        case .cloudflareRecovery:
            return viewModel.isCompletingCloudflareChallenge
        }
    }

    private var actionTitle: String {
        switch presentationState {
        case .login:
            return viewModel.isSyncingLoginSession ? "同步中…" : "完成登录"
        case .cloudflareRecovery:
            return viewModel.isCompletingCloudflareChallenge ? "重试中…" : "完成验证并重试"
        }
    }

    private var isActionEnabled: Bool {
        guard webViewBox.webView != nil else {
            return false
        }
        guard !webViewBox.isLoading else {
            return false
        }
        guard !isRunningAction else {
            return false
        }

        switch presentationState {
        case .login:
            return viewModel.canSyncLoginSession
        case .cloudflareRecovery:
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                HStack(spacing: 20) {
                    Button(action: webViewBox.goBack) {
                        Image(systemName: "chevron.backward")
                            .font(.body)
                    }
                    .disabled(!webViewBox.canGoBack)

                    Button(action: webViewBox.goForward) {
                        Image(systemName: "chevron.forward")
                            .font(.body)
                    }
                    .disabled(!webViewBox.canGoForward)
                }
                .foregroundStyle(.primary)

                Spacer()

                Button(action: performPrimaryAction) {
                    HStack(spacing: 6) {
                        if isRunningAction {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                        }
                        Text(actionTitle)
                    }
                }
                .buttonStyle(FirePrimaryButtonStyle())
                .disabled(!isActionEnabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func performPrimaryAction() {
        switch presentationState {
        case .login:
            onLoginSync()
        case .cloudflareRecovery:
            onCloudflareRecoveryComplete()
        }
    }
}

private struct FireLoginErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FireTheme.warning)
                .font(.caption)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}

private struct FireAuthInfoBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(FireTheme.accent)
                .font(.caption)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}
