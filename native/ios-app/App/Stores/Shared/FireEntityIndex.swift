import Foundation

struct FireEntityIndex<ID: Hashable, Entity> {
    private(set) var entitiesByID: [ID: Entity] = [:]

    var isEmpty: Bool {
        entitiesByID.isEmpty
    }

    mutating func replaceAll(
        _ entities: [Entity],
        id: KeyPath<Entity, ID>
    ) {
        entitiesByID = Dictionary(
            uniqueKeysWithValues: entities.map { ($0[keyPath: id], $0) }
        )
    }

    mutating func upsert(
        _ entities: [Entity],
        id: KeyPath<Entity, ID>
    ) {
        for entity in entities {
            entitiesByID[entity[keyPath: id]] = entity
        }
    }

    mutating func removeAll() {
        entitiesByID.removeAll()
    }

    func entity(for id: ID) -> Entity? {
        entitiesByID[id]
    }

    func orderedValues(
        for orderedIDs: FireOrderedIDList<ID>
    ) -> [Entity] {
        orderedIDs.ids.compactMap { entitiesByID[$0] }
    }
}
