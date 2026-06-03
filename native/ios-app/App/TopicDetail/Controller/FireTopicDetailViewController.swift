import AsyncDisplayKit
import UIKit

/// Page coordinator for the topic-detail screen.
///
/// Owns:
/// - Page lifecycle (begin/end, initial load, message-bus subscription)
/// - `FireTopicDetailRootNode` and the `ASCollectionNode` feed surface
/// - Page-local ephemeral UI state (quick reply draft, presented modal)
/// - Toolbar actions (share, bookmark, topic actions)
/// - Route-anchor and pending-scroll-target handling
///
/// Does NOT own:
/// - Store state (`FireTopicDetailStore` remains the entity source of truth)
/// - Node creation details (delegated to feed coordinator in Task 4)
@MainActor
final class FireTopicDetailViewController: UIViewController {

    // MARK: - Input

    let viewModel: FireAppViewModel
    let row: FireTopicRowPresentation
    let scrollToPostNumber: UInt32?

    // MARK: - Root Node

    private let rootNode: FireTopicDetailRootNode

    // MARK: - Init

    init(
        viewModel: FireAppViewModel,
        row: FireTopicRowPresentation,
        scrollToPostNumber: UInt32?
    ) {
        self.viewModel = viewModel
        self.row = row
        self.scrollToPostNumber = scrollToPostNumber
        self.rootNode = FireTopicDetailRootNode()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        view = rootNode.view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigationBar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    // MARK: - Navigation Bar

    private func configureNavigationBar() {
        navigationItem.title = "话题"
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
    }
}
