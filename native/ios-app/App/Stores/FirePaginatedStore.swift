import Foundation

@MainActor
class FirePaginatedStore<Item>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var blockingErrorMessage: String?
    @Published private(set) var nonBlockingErrorMessage: String?

    private var nextOffset: UInt32?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0

    var hasMore: Bool {
        nextOffset != nil
    }

    var currentNextOffset: UInt32? {
        nextOffset
    }

    func load(forceRefresh: Bool = false) {
        guard forceRefresh || !hasLoadedOnce else { return }
        startLoad(offset: nil, reset: true)
    }

    func loadAsync(forceRefresh: Bool = false) async {
        guard forceRefresh || !hasLoadedOnce else { return }
        await performLoad(offset: nil, reset: true)
    }

    func loadMore() {
        guard let nextOffset else { return }
        startLoad(offset: nextOffset, reset: false)
    }

    func loadMoreAsync() async {
        guard let nextOffset else { return }
        await performLoad(offset: nextOffset, reset: false)
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration = loadGeneration &+ 1
        items = []
        nextOffset = nil
        isLoading = false
        isLoadingMore = false
        hasLoadedOnce = false
        blockingErrorMessage = nil
        nonBlockingErrorMessage = nil
    }

    func clearErrors() {
        blockingErrorMessage = nil
        nonBlockingErrorMessage = nil
    }

    func clearBlockingError() {
        blockingErrorMessage = nil
    }

    func clearNonBlockingError() {
        nonBlockingErrorMessage = nil
    }

    func recordFailure(_ message: String, isBlocking: Bool = true) {
        if isBlocking {
            blockingErrorMessage = message
        } else {
            nonBlockingErrorMessage = message
        }
    }

    func applyPage(_ result: PageResult, reset: Bool) {
        items = reset ? result.items : mergeItems(existing: items, incoming: result.items)
        nextOffset = result.nextOffset
        hasLoadedOnce = true
        clearErrors()
    }

    func updateItems(_ nextItems: [Item]) {
        items = nextItems
    }

    struct PageResult {
        let items: [Item]
        let nextOffset: UInt32?
        let loadedOffset: UInt32?
        let isCached: Bool

        init(
            items: [Item],
            nextOffset: UInt32?,
            loadedOffset: UInt32? = nil,
            isCached: Bool = false
        ) {
            self.items = items
            self.nextOffset = nextOffset
            self.loadedOffset = loadedOffset
            self.isCached = isCached
        }
    }

    func fetchPage(offset: UInt32?) async throws -> PageResult {
        fatalError("Subclasses must override fetchPage(offset:)")
    }

    func mergeItems(existing: [Item], incoming: [Item]) -> [Item] {
        existing + incoming
    }

    func handlePageLoadError(_ error: Error, offset: UInt32?) async -> Bool {
        false
    }

    private func startLoad(offset: UInt32?, reset: Bool) {
        if reset {
            loadTask?.cancel()
        } else {
            guard !isLoading, !isLoadingMore else { return }
        }

        loadGeneration = loadGeneration &+ 1
        let generation = loadGeneration
        if reset {
            isLoading = true
            isLoadingMore = false
            blockingErrorMessage = nil
        } else {
            isLoadingMore = true
            nonBlockingErrorMessage = nil
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.performLoadBody(offset: offset, reset: reset, generation: generation)
        }
    }

    private func performLoad(offset: UInt32?, reset: Bool) async {
        if reset {
            loadTask?.cancel()
        } else {
            guard !isLoading, !isLoadingMore else { return }
        }

        loadGeneration = loadGeneration &+ 1
        let generation = loadGeneration
        if reset {
            isLoading = true
            isLoadingMore = false
            blockingErrorMessage = nil
        } else {
            isLoadingMore = true
            nonBlockingErrorMessage = nil
        }

        await performLoadBody(offset: offset, reset: reset, generation: generation)
    }

    private func performLoadBody(offset: UInt32?, reset: Bool, generation: UInt64) async {
        defer {
            if generation == loadGeneration {
                isLoading = false
                isLoadingMore = false
                loadTask = nil
            }
        }

        do {
            let page = try await fetchPage(offset: offset)
            guard !Task.isCancelled, generation == loadGeneration else { return }
            applyPage(page, reset: reset)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == loadGeneration else { return }
            let handled = await handlePageLoadError(error, offset: offset)
            if !handled {
                recordFailure(error.localizedDescription, isBlocking: reset && !hasLoadedOnce)
            }
        }
    }
}
