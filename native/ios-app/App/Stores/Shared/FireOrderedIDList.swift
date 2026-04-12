import Foundation

struct FireOrderedIDList<ID: Hashable> {
    private(set) var ids: [ID] = []
    private var idSet: Set<ID> = []

    init(ids: [ID] = []) {
        replace(with: ids)
    }

    var isEmpty: Bool {
        ids.isEmpty
    }

    mutating func replace(with newIDs: [ID]) {
        ids = []
        idSet = []
        append(newIDs)
    }

    mutating func append(_ newIDs: [ID]) {
        for id in newIDs {
            guard idSet.insert(id).inserted else { continue }
            ids.append(id)
        }
    }

    mutating func removeAll() {
        ids.removeAll()
        idSet.removeAll()
    }
}
