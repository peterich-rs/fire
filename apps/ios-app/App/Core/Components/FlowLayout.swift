import SwiftUI

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    var spacing: CGFloat = 6
    var fallbackWidth: CGFloat? = nil
    var data: Data
    @ViewBuilder var content: (Data.Element) -> Content

    @State private var sizes: [Data.Element: CGSize] = [:]
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        let maxWidth = resolvedMaxWidth(containerWidth > 0 ? containerWidth : nil)
        let placed = placement(maxWidth: maxWidth)
        ZStack(alignment: .topLeading) {
            ForEach(Array(data), id: \.self) { element in
                content(element)
                    .fixedSize()
                    .background(childSizeReader(for: element))
                    .offset(
                        x: placed.frames[element]?.minX ?? 0,
                        y: placed.frames[element]?.minY ?? 0
                    )
            }
        }
        .frame(maxWidth: .infinity, minHeight: placed.height, alignment: .topLeading)
        .background(widthReader)
        .onPreferenceChange(FlowWidthKey.self) { newWidth in
            guard newWidth > 0, abs(containerWidth - newWidth) > 0.5 else { return }
            containerWidth = newWidth
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: FlowWidthKey.self, value: proxy.size.width)
        }
    }

    private func childSizeReader(for element: Data.Element) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: FlowChildSizeKey<Data.Element>.self, value: [element: proxy.size])
        }
        .onPreferenceChange(FlowChildSizeKey<Data.Element>.self) { update in
            let measured = update.filter { $0.value.width > 0 || $0.value.height > 0 }
            guard !measured.isEmpty else { return }
            var next = sizes
            for (key, size) in measured where next[key] != size {
                next[key] = size
            }
            if next != sizes {
                sizes = next
            }
        }
    }

    private func resolvedMaxWidth(_ proposal: CGFloat?) -> CGFloat {
        if let proposal, proposal.isFinite, proposal > 0 {
            return proposal
        }
        if let fallbackWidth, fallbackWidth.isFinite, fallbackWidth > 0 {
            return fallbackWidth
        }
        return max(UIScreen.main.bounds.width - 120, 180)
    }

    private func placement(maxWidth: CGFloat) -> FlowPlacement<Data.Element> {
        var frames: [Data.Element: CGRect] = [:]
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for element in data {
            let size = sizes[element] ?? .zero
            if cursorX > 0, cursorX + size.width > maxWidth {
                cursorX = 0
                cursorY += lineHeight + spacing
                lineHeight = 0
            }
            frames[element] = CGRect(origin: CGPoint(x: cursorX, y: cursorY), size: size)
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let height = cursorY + lineHeight
        return FlowPlacement(frames: frames, height: height)
    }
}

private struct FlowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FlowPlacement<Element: Hashable> {
    var frames: [Element: CGRect]
    var height: CGFloat
}

private struct FlowChildSizeKey<Element: Hashable>: PreferenceKey {
    static var defaultValue: [Element: CGSize] { [:] }

    static func reduce(value: inout [Element: CGSize], nextValue: () -> [Element: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
