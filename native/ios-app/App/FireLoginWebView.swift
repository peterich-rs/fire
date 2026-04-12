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
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        pageTitle = webView.title ?? "LinuxDo Login"
        currentURL = webView.url?.host ?? webView.url?.absoluteString
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

final class FireLoginWebViewProbeBridge: NSObject, WKHTTPCookieStoreObserver {
    private weak var observedWebView: WKWebView?
    private weak var observedCookieStore: WKHTTPCookieStore?
    private let onProbeRequested: (WKWebView) -> Void

    init(onProbeRequested: @escaping (WKWebView) -> Void) {
        self.onProbeRequested = onProbeRequested
    }

    deinit {
        observedCookieStore?.remove(self)
    }

    func attach(to webView: WKWebView) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        if observedCookieStore !== cookieStore {
            observedCookieStore?.remove(self)
            cookieStore.add(self)
            observedCookieStore = cookieStore
        }
        observedWebView = webView
    }

    func detach() {
        observedCookieStore?.remove(self)
        observedCookieStore = nil
        observedWebView = nil
    }

    func requestProbe() {
        guard let observedWebView else {
            return
        }
        onProbeRequested(observedWebView)
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        requestProbe()
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
        private let probeBridge: FireLoginWebViewProbeBridge

        init(
            webViewBox: FireWebViewBox,
            onNavigationStateChange: @escaping (WKWebView) -> Void
        ) {
            self.probeBridge = FireLoginWebViewProbeBridge { webView in
                webViewBox.syncState(from: webView)
                onNavigationStateChange(webView)
            }
        }

        func attach(to webView: WKWebView) {
            probeBridge.attach(to: webView)
        }

        func detach() {
            probeBridge.detach()
        }

        private func handleStateChange(for webView: WKWebView) {
            probeBridge.attach(to: webView)
            probeBridge.requestProbe()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            handleStateChange(for: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            handleStateChange(for: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            handleStateChange(for: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            handleStateChange(for: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleStateChange(for: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            handleStateChange(for: webView)
        }
    }
}

struct FireLoginScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: FireAppViewModel
    @StateObject private var webViewBox = FireWebViewBox()

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

                FireLoginWebView(
                    url: URL(string: "https://linux.do")!,
                    webViewBox: webViewBox,
                    onNavigationStateChange: { webView in
                        viewModel.refreshLoginSyncReadiness(from: webView)
                    }
                )
                .frame(maxHeight: .infinity)
            }
            .background(Color(.systemBackground))
            .navigationTitle("登录 LinuxDo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
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
                FireLoginBottomBar(
                    viewModel: viewModel,
                    webViewBox: webViewBox,
                    onSync: {
                        guard let webView = webViewBox.webView else { return }
                        viewModel.completeLogin(from: webView)
                    }
                )
            }
            .onAppear {
                viewModel.setAPMRoute("auth.login")
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let webView = webViewBox.webView else {
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

private struct FireLoginBottomBar: View {
    @ObservedObject var viewModel: FireAppViewModel
    @ObservedObject var webViewBox: FireWebViewBox
    let onSync: () -> Void

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

                Button(action: onSync) {
                    HStack(spacing: 6) {
                        if viewModel.isSyncingLoginSession {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                        }
                        Text(viewModel.isSyncingLoginSession ? "同步中…" : "完成登录")
                    }
                }
                .buttonStyle(FirePrimaryButtonStyle())
                .disabled(
                    webViewBox.webView == nil
                        || viewModel.isSyncingLoginSession
                        || !viewModel.canSyncLoginSession
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
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
