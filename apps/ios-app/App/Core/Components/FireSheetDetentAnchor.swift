import SwiftUI
import UIKit

struct FireSheetDetentAnchor: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> FireSheetDetentAnchorController {
        FireSheetDetentAnchorController()
    }

    func updateUIViewController(_ controller: FireSheetDetentAnchorController, context: Context) {
        controller.applyDetents()
    }
}

final class FireSheetDetentAnchorController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isHidden = true
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyDetents()
    }

    func applyDetents() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let sheet = self.nearestSheet() else { return }
            let medium = UISheetPresentationController.Detent.Identifier.medium
            let large = UISheetPresentationController.Detent.Identifier.large
            if sheet.detents.map(\.identifier) != [medium, large] {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
        }
    }

    private func nearestSheet() -> UISheetPresentationController? {
        var current: UIViewController? = self
        while let controller = current {
            if let sheet = controller.sheetPresentationController {
                return sheet
            }
            current = controller.parent ?? controller.navigationController ?? controller.presentingViewController
        }
        return nil
    }
}
