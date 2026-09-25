import UIKit

extension FireOnboardingCredentialFormView {
    func setupLoginButton() {
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = "登录"
        configuration.baseBackgroundColor = .systemOrange
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        loginButton.configuration = configuration
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        loginButton.fireBindPressBounce(.button)
        loginButton.isEnabled = false

        contentView.addSubview(loginButton)

        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: optionsRow.bottomAnchor, constant: 16),
            loginButton.leadingAnchor.constraint(equalTo: identifierField.leadingAnchor),
            loginButton.trailingAnchor.constraint(equalTo: identifierField.trailingAnchor),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
    @objc func loginTapped() {
        guard let identifier = identifierField.text?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let password = passwordField.text,
              !identifier.isEmpty,
              !password.isEmpty
        else {
            return
        }
        endEditing(true)
        onLoginTapped?(identifier, password, isRememberChecked)
    }
}
