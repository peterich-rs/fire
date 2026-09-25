import Combine
import SwiftUI
import UIKit

struct FireDraftsControllerHost: UIViewControllerRepresentable {
    let viewModel: FireAppViewModel

    func makeUIViewController(context: Context) -> FireDraftsViewController {
        FireDraftsViewController(viewModel: viewModel)
    }

    func updateUIViewController(
        _ uiViewController: FireDraftsViewController,
        context: Context
    ) {}
}
