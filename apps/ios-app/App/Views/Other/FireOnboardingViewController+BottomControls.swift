import SwiftUI
import UIKit

extension FireOnboardingViewController {
    func configureDeveloperToolsButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "ant")
        configuration.baseForegroundColor = FireTheme.uiTertiaryInk
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        developerToolsButton.configuration = configuration
        developerToolsButton.accessibilityLabel = "开发者工具"
        developerToolsButton.translatesAutoresizingMaskIntoConstraints = false
        developerToolsButton.addTarget(self, action: #selector(developerToolsButtonTapped), for: .touchUpInside)
        developerToolsButton.fireBindPressBounce(.compact)
        view.addSubview(developerToolsButton)
        NSLayoutConstraint.activate([
            developerToolsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            developerToolsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
        ])
    }
    func configureFeedbackButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "bubble.left.and.exclamationmark.bubble.right")
        configuration.baseForegroundColor = FireTheme.uiTertiaryInk
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        feedbackButton.configuration = configuration
        feedbackButton.accessibilityLabel = "反馈与建议"
        feedbackButton.translatesAutoresizingMaskIntoConstraints = false
        feedbackButton.addTarget(self, action: #selector(feedbackButtonTapped), for: .touchUpInside)
        feedbackButton.fireBindPressBounce(.compact)
        view.addSubview(feedbackButton)
        NSLayoutConstraint.activate([
            feedbackButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            feedbackButton.trailingAnchor.constraint(equalTo: developerToolsButton.leadingAnchor, constant: -2),
        ])
    }
    func configureBottomControls() {
        errorBanner.onDismiss = { [weak self] in
            self?.viewModel.dismissError()
        }

        phaseContainerView.translatesAutoresizingMaskIntoConstraints = false
        // Hug the active phase content instead of expanding into a tall empty well.
        phaseContainerView.setContentHuggingPriority(.required, for: .vertical)
        phaseContainerView.setContentCompressionResistancePriority(.required, for: .vertical)

        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.spacing = 12
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(errorBanner)
        bottomStack.addArrangedSubview(phaseContainerView)
        bottomStack.setContentHuggingPriority(.required, for: .vertical)
        bottomStack.setContentCompressionResistancePriority(.required, for: .vertical)
    }
    @objc func developerToolsButtonTapped() {
        let controller = FireHosting.controller(
            rootView: FireDeveloperToolsView(viewModel: viewModel),
            title: "开发者工具"
        )
        // Show nav chrome only for the pushed diagnostics page; login itself stays bar-less.
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.pushViewController(controller, animated: true)
    }
    @objc func feedbackButtonTapped() {
        FireFeedbackPresenter.present(
            from: self,
            appViewModel: viewModel,
            source: "onboarding"
        )
    }
}
