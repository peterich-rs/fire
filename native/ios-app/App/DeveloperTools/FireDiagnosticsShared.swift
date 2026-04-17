import Foundation
import SwiftUI
import UIKit

// MARK: - Presentation Helpers

enum FireDiagnosticsPresentation {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static func timestamp(_ unixMilliseconds: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixMilliseconds) / 1000)
        return timestampFormatter.string(from: date)
    }

    static func byteSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func compactURL(_ rawValue: String) -> String {
        guard let url = URL(string: rawValue) else {
            return rawValue
        }

        let path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }

    static func outcome(_ trace: NetworkTraceSummaryState) -> String {
        switch trace.outcome {
        case .inProgress:
            return "进行中"
        case .succeeded:
            return "成功"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
        }
    }
}

// MARK: - Text View

struct FireDiagnosticsTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            uiView.setContentOffset(.zero, animated: false)
        }
    }
}

// MARK: - Share Sheet

struct FireActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let subject: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.setValue(subject, forKey: "subject")
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Mini Stat

struct FireDiagnosticsMiniStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
