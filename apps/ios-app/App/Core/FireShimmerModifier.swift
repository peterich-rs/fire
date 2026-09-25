import SwiftUI

struct FireShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    private let duration: Double = 1.5

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                FireTheme.softSurface.opacity(0),
                                FireTheme.softSurface.opacity(0.55),
                                FireTheme.softSurface.opacity(0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 1.4)
                        .offset(x: phase * proxy.size.width)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                phase = -1
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func fireShimmer() -> some View {
        modifier(FireShimmerModifier())
    }
}
