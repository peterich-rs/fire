import SwiftUI
import UIKit

enum FireScopedTopicListDisplayState: Equatable, Hashable {
    case loading
    case blockingError(message: String)
    case empty(nonBlockingErrorMessage: String?)
    case content(nonBlockingErrorMessage: String?)

    static func resolve(
        hasResolvedCurrentScope: Bool,
        hasRows: Bool,
        errorMessage: String?
    ) -> Self {
        if !hasResolvedCurrentScope {
            if let errorMessage {
                return .blockingError(message: errorMessage)
            }
            return .loading
        }

        if hasRows {
            return .content(nonBlockingErrorMessage: errorMessage)
        }

        return .empty(nonBlockingErrorMessage: errorMessage)
    }
}

@MainActor
final class FireFilteredTopicListViewModel: ObservableObject {
    typealias FetchFilteredTopics = @MainActor (TopicListQueryState) async throws -> TopicListState

    @Published var selectedKind: TopicListKindState = .latest
    @Published private(set) var rows: [FireTopicRowPresentation] = []
    @Published private(set) var renderedKind: TopicListKindState?
    @Published private(set) var nextPage: UInt32?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let fetchFilteredTopics: FetchFilteredTopics
    private let categorySlug: String?
    private let categoryId: UInt64?
    private let parentCategorySlug: String?
    private let tag: String?
    private var loadGeneration: UInt64 = 0

    init(
        appViewModel: FireAppViewModel,
        categorySlug: String?,
        categoryId: UInt64?,
        parentCategorySlug: String?,
        tag: String?
    ) {
        self.fetchFilteredTopics = { query in
            try await appViewModel.fetchFilteredTopicList(query: query)
        }
        self.categorySlug = categorySlug
        self.categoryId = categoryId
        self.parentCategorySlug = parentCategorySlug
        self.tag = tag
    }

    init(
        categorySlug: String?,
        categoryId: UInt64?,
        parentCategorySlug: String?,
        tag: String?,
        fetchFilteredTopics: @escaping FetchFilteredTopics
    ) {
        self.fetchFilteredTopics = fetchFilteredTopics
        self.categorySlug = categorySlug
        self.categoryId = categoryId
        self.parentCategorySlug = parentCategorySlug
        self.tag = tag
    }

    var hasResolvedCurrentKind: Bool {
        renderedKind == selectedKind
    }

    var displayedRows: [FireTopicRowPresentation] {
        hasResolvedCurrentKind ? rows : []
    }

    var currentKindNextPage: UInt32? {
        hasResolvedCurrentKind ? nextPage : nil
    }

    var currentKindDisplayState: FireScopedTopicListDisplayState {
        FireScopedTopicListDisplayState.resolve(
            hasResolvedCurrentScope: hasResolvedCurrentKind,
            hasRows: !displayedRows.isEmpty,
            errorMessage: errorMessage
        )
    }

    func loadIfNeeded() async {
        guard (!hasResolvedCurrentKind || rows.isEmpty), !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        await load(page: nil, reset: true)
    }

    func selectKind(_ kind: TopicListKindState, animation: Animation? = nil) async {
        guard selectedKind != kind else { return }
        if let animation {
            withAnimation(animation) {
                selectedKind = kind
            }
        } else {
            selectedKind = kind
        }
        await load(page: nil, reset: true)
    }

    func loadMore() async {
        guard let nextPage = currentKindNextPage else { return }
        guard !isLoading, !isLoadingMore else { return }
        await load(page: nextPage, reset: false)
    }

    private func load(page: UInt32?, reset: Bool) async {
        let requestKind = selectedKind
        let requestPage = reset ? nil : page
        loadGeneration &+= 1
        let generation = loadGeneration

        if reset {
            isLoading = true
            isLoadingMore = false
            nextPage = nil
        } else {
            guard !isLoading else { return }
            isLoadingMore = true
        }
        errorMessage = nil

        defer {
            if generation == loadGeneration {
                isLoading = false
                isLoadingMore = false
            }
        }

        do {
            let response = try await fetchFilteredTopics(
                TopicListQueryState(
                    kind: requestKind,
                    page: requestPage,
                    topicIds: [],
                    order: nil,
                    ascending: nil,
                    categorySlug: categorySlug,
                    categoryId: categoryId,
                    parentCategorySlug: parentCategorySlug,
                    tag: tag,
                    additionalTags: [],
                    matchAllTags: false
                )
            )
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }

            if reset {
                rows = response.rows
            } else {
                rows = mergeRows(existing: rows, incoming: response.rows)
            }
            renderedKind = requestKind
            nextPage = response.nextPage
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func mergeRows(
        existing: [FireTopicRowPresentation],
        incoming: [FireTopicRowPresentation]
    ) -> [FireTopicRowPresentation] {
        var merged = existing
        let existingIDs = Set(existing.map(\.topic.id))
        merged.append(contentsOf: incoming.filter { !existingIDs.contains($0.topic.id) })
        return merged
    }
}

/// Legacy SwiftUI entry for category browser NavigationLink.
/// Authoritative implementation is `FireFilteredTopicListViewController`.
struct FireFilteredTopicListView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let title: String
    let categorySlug: String?
    let categoryId: UInt64?
    let parentCategorySlug: String?
    let tag: String?

    var body: some View {
        FireFilteredTopicListControllerHost(
            viewModel: viewModel,
            title: title,
            categorySlug: categorySlug,
            categoryId: categoryId,
            parentCategorySlug: parentCategorySlug,
            tag: tag
        )
        .ignoresSafeArea()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
