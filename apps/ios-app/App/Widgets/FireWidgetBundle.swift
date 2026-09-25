import SwiftUI
import WidgetKit

@main
struct FireWidgetBundle: WidgetBundle {
    var body: some Widget {
        FireSmallWidget()
        FireMediumWidget()
        FireLargeWidget()
    }
}
