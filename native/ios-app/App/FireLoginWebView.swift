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
        NavigationStack {
            FireLoginWebView(
                url: URL(string: "https://linux.do")!,
                webViewBox: webViewBox
            )
            .navigationTitle(webViewBox.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                if let currentURL = webViewBox.currentURL {
                    Text(currentURL)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sync") {
                        guard let webView = webViewBox.webView else {
                            return
                        }
                        viewModel.completeLogin(from: webView)
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        webViewBox.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!webViewBox.canGoBack)

                    Button {
                        webViewBox.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!webViewBox.canGoForward)

                    Spacer()

                    if webViewBox.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        webViewBox.loadHome()
                    } label: {
                        Image(systemName: "house")
                    }

                    Button {
                        webViewBox.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}
