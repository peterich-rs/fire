import UIKit

extension FireOnboardingViewController {
    func recoverCloudflare() {
        guard !cfRetryUsed else {
            abortLoginAttempt(
                message: Self.loginCloudflareFailureMessage(reason: "failed"),
                source: "recoverCloudflare already used"
            )
            return
        }
        cfRetryUsed = true
        logAuth("recoverCloudflare begin")

        Task {
            guard let dialog = captchaDialog else {
                abortLoginAttempt(
                    message: Self.loginCloudflareFailureMessage(reason: "failed"),
                    source: "recoverCloudflare missing dialog"
                )
                return
            }
            do {
                try await viewModel.recoverLoginCloudflareChallenge(in: dialog.webView)
            } catch {
                abortLoginAttempt(
                    message: Self.loginCloudflareFailureMessage(
                        reason: FireAppViewModel.cloudflareChallengeReason(from: error)
                    ),
                    source: "recoverCloudflare: \(error.localizedDescription)"
                )
                return
            }
            logAuth("recoverCloudflare done; retrying login in dialog")
            dialog.retryAfterCloudflareRecovery()
        }
    }
    static func loginCloudflareFailureMessage(reason: String?) -> String {
        switch reason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cooldown":
            return "网络验证暂时冷却中，可稍后重试或手动完成验证"
        case "cancelled":
            return "已取消网络验证，账号密码仍保留，可继续登录"
        case "in_progress":
            return "网络验证进行中，请稍候"
        case "background_suppressed":
            return "需要前台完成网络验证，请重试"
        default:
            return "网络验证未完成，请重试或手动验证后继续"
        }
    }
    func presentWebViewBrowser(
        url: URL,
        autoStartExternalLogin: FireExternalLoginMethod? = nil
    ) {
        let browser = FireWebViewBrowserViewController(
            url: url,
            viewModel: viewModel,
            autoStartExternalLogin: autoStartExternalLogin
        )
        browser.modalPresentationStyle = .fullScreen
        present(browser, animated: true)
    }
}
