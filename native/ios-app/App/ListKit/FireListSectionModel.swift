import Foundation

struct FireListSectionModel<SectionID: Hashable, ItemID: Hashable>: Hashable {
    let id: SectionID
    let items: [ItemID]

    init(
        id: SectionID,
        items: [ItemID]
    ) {
        self.id = id
        self.items = items
    }
}
