import SwiftUI
import WebKit

final class FireWebViewBox: ObservableObject {
    weak var webView: WKWebView?
}

struct FireLoginWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var webViewBox: FireWebViewBox

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        webViewBox.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(webViewBox: webViewBox)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let webViewBox: FireWebViewBox

        init(webViewBox: FireWebViewBox) {
            self.webViewBox = webViewBox
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webViewBox.webView = webView
        }
    }
}

struct FireLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: FireAppViewModel
    @StateObject private var webViewBox = FireWebViewBox()

    var body: some View {
        NavigationStack {
            FireLoginWebView(
                url: URL(string: "https://linux.do")!,
                webViewBox: webViewBox
            )
            .navigationTitle("LinuxDo Login")
            .navigationBarTitleDisplayMode(.inline)
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
            }
        }
    }
}
