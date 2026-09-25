import UIKit

extension FireOnboardingViewController {
    func showSecondFactorPrompt(requirement: SecondFactorRequirementState) {
        let isFirstAttempt = !hasShownSecondFactor
        hasShownSecondFactor = true

        let fallbackHint: String?
        if !requirement.totpEnabled && (requirement.backupEnabled || requirement.securityKeyEnabled) {
            fallbackHint = "备用码或安全密钥请通过其他方式登录。"
        } else {
            fallbackHint = nil
        }
        let baseMessage = requirement.message ?? "请输入验证器中的 6 位代码"
        let message = [baseMessage, fallbackHint].compactMap { $0 }.joined(separator: "\n")

        let alert = UIAlertController(
            title: isFirstAttempt ? "两步验证" : "验证码错误",
            message: message,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "6 位验证码"
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
        }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            guard let code = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !code.isEmpty
            else {
                return
            }
            self.captchaDialog?.retryWithSecondFactor(code)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.abortLoginAttempt(message: nil, source: "secondFactor.cancel")
        })
        (captchaDialog ?? self).present(alert, animated: true)
    }
}
