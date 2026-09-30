import UIKit

enum FireSharePresenter {
    @MainActor
    static func present(_ url: URL) {
        guard let presenter = topPresenter() else { return }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.safeAreaInsets.top + 24,
                width: 1,
                height: 1
            )
        }
        presenter.present(controller, animated: true)
    }

    @MainActor
    private static func topPresenter() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var presenter = window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        return presenter
    }
}
