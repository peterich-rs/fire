import SwiftUI

// MARK: - Scene Background

struct FireSceneBackground: View {
    var body: some View {
        LinearGradient(
            colors: [FireTheme.canvasTop, FireTheme.canvasMid, FireTheme.canvasBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(FireTheme.accent.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 54)
                .offset(x: -80, y: -90)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(FireTheme.accentSoft.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 90, y: 80)
        }
        .ignoresSafeArea()
    }
}
