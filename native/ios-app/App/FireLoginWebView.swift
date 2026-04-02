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

struct FireLoginWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var webViewBox: FireWebViewBox

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        webViewBox.attach(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        webViewBox.webView = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(webViewBox: webViewBox)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let webViewBox: FireWebViewBox

        init(webViewBox: FireWebViewBox) {
            self.webViewBox = webViewBox
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            webViewBox.syncState(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            webViewBox.syncState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webViewBox.syncState(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            webViewBox.syncState(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            webViewBox.syncState(from: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webViewBox.syncState(from: webView)
        }
    }
}

struct FireLoginScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FireAppViewModel
    @StateObject private var webViewBox = FireWebViewBox()

    var body: some View {
        ZStack {
            FireSceneBackground()

            VStack(spacing: 14) {
                FireLoginTopBar(
                    pageTitle: webViewBox.pageTitle,
                    currentURL: webViewBox.currentURL,
                    isLoading: webViewBox.isLoading
                ) {
                    dismiss()
                }

                if let errorMessage = viewModel.errorMessage {
                    FireLoginErrorBanner(
                        message: errorMessage,
                        onDismiss: { viewModel.dismissError() }
                    )
                }

                FireLoginBrowserFrame {
                    FireLoginWebView(
                        url: URL(string: "https://linux.do")!,
                        webViewBox: webViewBox
                    )
                }
                .frame(maxHeight: .infinity)

                FireLoginBottomBar(
                    viewModel: viewModel,
                    webViewBox: webViewBox,
                    onSync: {
                        guard let webView = webViewBox.webView else {
                            return
                        }
                        viewModel.completeLogin(from: webView)
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct FireLoginTopBar: View {
    let pageTitle: String
    let currentURL: String?
    let isLoading: Bool
    let onClose: () -> Void

    var body: some View {
        FireLoginChromePanel {
            HStack(spacing: 14) {
                Button(action: onClose) {
                    FireToolbarIcon(symbol: "xmark")
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(pageTitle)
                        .font(.headline)
                        .foregroundStyle(FireTheme.ink)
                        .lineLimit(1)

                    Text(currentURL ?? "linux.do")
                        .font(.caption)
                        .foregroundStyle(FireTheme.tertiaryInk)
                        .lineLimit(1)
                }

                Spacer()

                FireLoginBadge(
                    label: isLoading ? "Loading" : "Ready",
                    accent: isLoading ? FireTheme.accent : FireTheme.success
                )
            }
        }
    }
}

private struct FireLoginBottomBar: View {
    @ObservedObject var viewModel: FireAppViewModel
    @ObservedObject var webViewBox: FireWebViewBox
    let onSync: () -> Void

    var body: some View {
        FireLoginChromePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        FireLoginCommandButton(
                            symbol: "chevron.backward",
                            disabled: !webViewBox.canGoBack,
                            action: webViewBox.goBack
                        )
                        FireLoginCommandButton(
                            symbol: "chevron.forward",
                            disabled: !webViewBox.canGoForward,
                            action: webViewBox.goForward
                        )
                        FireLoginCommandButton(
                            symbol: "house",
                            disabled: false,
                            action: webViewBox.loadHome
                        )
                        FireLoginCommandButton(
                            symbol: "arrow.clockwise",
                            disabled: false,
                            action: webViewBox.reload
                        )
                    }

                    Spacer(minLength: 8)

                    Button(action: onSync) {
                        HStack(spacing: 8) {
                            if viewModel.isSyncingLoginSession {
                                ProgressView()
                                    .tint(.white)
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(viewModel.isSyncingLoginSession ? "同步中…" : "Sync Session")
                        }
                    }
                        .buttonStyle(FirePrimaryButtonStyle())
                        .disabled(webViewBox.webView == nil || viewModel.isSyncingLoginSession)
                }

                Text(
                    viewModel.isSyncingLoginSession
                        ? "正在读取当前页面 HTML、Cookie 和 CSRF，并把登录态同步回共享 core。"
                        : webViewBox.isLoading
                        ? "页面还在跳转或加载，等状态稳定后再同步会更稳。"
                        : "完成登录后点击 Sync Session，把 cookie、bootstrap 和 CSRF 同步回共享 core。"
                )
                .font(.footnote)
                .foregroundStyle(FireTheme.subtleInk)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FireLoginErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FireTheme.warning)
                .font(.subheadline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(FireTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FireTheme.tertiaryInk)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FireTheme.softSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(FireTheme.warning.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

private struct FireLoginBrowserFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(FireTheme.chromeStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(FireTheme.chromeBorder, lineWidth: 1)
                )

            content
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(6)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 28, y: 16)
    }
}

private struct FireLoginChromePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [FireTheme.chromeStrong, FireTheme.chrome],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(FireTheme.chromeBorder, lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
    }
}

private struct FireLoginCommandButton: View {
    let symbol: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(disabled ? FireTheme.tertiaryInk : FireTheme.inverseInk)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(disabled ? FireTheme.track : FireTheme.panel)
                        .overlay(
                            Circle()
                                .strokeBorder(disabled ? FireTheme.divider : FireTheme.inverseDivider, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct FireLoginBadge: View {
    let label: String
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FireTheme.subtleInk)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(FireTheme.softSurface)
        )
    }
}
