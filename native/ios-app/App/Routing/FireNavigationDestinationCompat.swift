import SwiftUI

extension View {
    func fireNavigationDestination<Item: Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        navigationDestination(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        item.wrappedValue = nil
                    }
                }
            )
        ) {
            if let value = item.wrappedValue {
                destination(value)
            }
        }
    }
}
