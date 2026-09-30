import SwiftUI

struct FireModalNavigation<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationView {
            content()
        }
        .navigationViewStyle(.stack)
    }
}
