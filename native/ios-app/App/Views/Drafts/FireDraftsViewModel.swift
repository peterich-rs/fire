import Combine
import SwiftUI
import UIKit

@MainActor
final class FireDraftsViewModel: ObservableObject {
    @Published private(set) var drafts: [DraftState] = []
    @Published private(set) var hasMore = true
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var errorMessage: String?

    private static let pageSize: UInt32 = 20
    private let appViewModel: FireAppViewModel

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    func loadIfNeeded() async {
        guard drafts.isEmpty, !isLoading else { return }
        await load(reset: true)
    }

    func refresh() async {
        await load(reset: true)
    }

    func loadMoreIfNeeded(currentDraftKey: String) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard drafts.last?.draftKey == currentDraftKey else { return }
        await load(reset: false)
    }

    func deleteDraft(_ draft: DraftState) async {
        do {
            try await appViewModel.deleteDraft(
                draftKey: draft.draftKey,
                sequence: draft.sequence
            )
            drafts.removeAll { $0.draftKey == draft.draftKey }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    private func load(reset: Bool) async {
        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let offset: UInt32? = reset ? 0 : UInt32(drafts.count)
            let response = try await appViewModel.fetchDrafts(
                offset: offset,
                limit: Self.pageSize
            )
            if reset {
                drafts = response.drafts
            } else {
                let existingKeys = Set(drafts.map(\.draftKey))
                drafts.append(contentsOf: response.drafts.filter { !existingKeys.contains($0.draftKey) })
            }
            hasMore = response.hasMore
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
