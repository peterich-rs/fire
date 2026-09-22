import UIKit

@MainActor
extension FireTopicDetailViewController {
    func toggleTopicSearch() {
        if topicSearchBar.isHidden {
            showTopicSearch()
        } else {
            hideTopicSearch()
        }
    }

    func showTopicSearch() {
        topicSearchBar.isHidden = false
        layoutTopicSearchBar()
        updateFeedTopInset()
        topicSearchBar.focusInput()
        recomputeTopicSearch(scrollToActiveMatch: false)
    }

    func hideTopicSearch() {
        topicSearchQuery = ""
        topicSearchMatches = []
        topicSearchIndex = -1
        topicSearchBar.reset()
        topicSearchBar.isHidden = true
        view.endEditing(true)
        layoutTopicSearchBar()
        updateFeedTopInset()
        buildAndApplySnapshot()
    }

    func updateTopicSearchQuery(_ query: String) {
        topicSearchQuery = query
        recomputeTopicSearch(scrollToActiveMatch: true)
    }

    func recomputeTopicSearch(scrollToActiveMatch: Bool) {
        if topicSearchBar.isHidden && topicSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let previousPostID = activeTopicSearchMatch?.postID
        topicSearchMatches = FireTopicPresentation.topicSearchMatches(
            query: topicSearchQuery,
            posts: detailSnapshot.map(FireTopicDetailUiProjection.posts(from:)) ?? []
        )
        if topicSearchMatches.isEmpty {
            topicSearchIndex = -1
        } else if let previousPostID,
                  let index = topicSearchMatches.firstIndex(where: { $0.postID == previousPostID }) {
            topicSearchIndex = index
        } else {
            topicSearchIndex = 0
        }
        topicSearchBar.updateResult(index: topicSearchIndex, total: topicSearchMatches.count)
        buildAndApplySnapshot()
        if scrollToActiveMatch, let match = activeTopicSearchMatch {
            openPostNumber(match.postNumber)
        }
    }

    func navigateTopicSearch(delta: Int) {
        guard !topicSearchMatches.isEmpty else { return }
        let size = topicSearchMatches.count
        topicSearchIndex = (topicSearchIndex + delta + size) % size
        topicSearchBar.updateResult(index: topicSearchIndex, total: size)
        buildAndApplySnapshot()
        if let match = activeTopicSearchMatch {
            openPostNumber(match.postNumber)
        }
    }

    func layoutTopicSearchBar() {
        // Keep a non-zero frame even while hidden. Collapsing to 0×0 fights the
        // search bar's internal Auto Layout padding and spams unsatisfiable
        // constraint logs; top inset already uses `currentSearchBarHeight`
        // (0 when hidden) so chrome spacing stays correct.
        let width = view.bounds.width
        guard width > 1 else { return }
        let targetFrame = CGRect(
            x: 0,
            y: view.safeAreaInsets.top,
            width: width,
            height: 56
        )
        if topicSearchBar.frame != targetFrame {
            topicSearchBar.frame = targetFrame
        }
    }

    func updateFeedTopInset() {
        rootNode.updateTopChromeInset(currentSearchBarHeight)
    }

    func configureTopicSearchBar() {
        topicSearchBar.translatesAutoresizingMaskIntoConstraints = true
        topicSearchBar.autoresizingMask = [.flexibleWidth]
        topicSearchBar.isHidden = true
        topicSearchBar.onQueryChanged = { [weak self] query in
            self?.updateTopicSearchQuery(query)
        }
        topicSearchBar.onPrevious = { [weak self] in
            self?.navigateTopicSearch(delta: -1)
        }
        topicSearchBar.onNext = { [weak self] in
            self?.navigateTopicSearch(delta: 1)
        }
        topicSearchBar.onClose = { [weak self] in
            self?.hideTopicSearch()
        }
        view.addSubview(topicSearchBar)
    }
}
