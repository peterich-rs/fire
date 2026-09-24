import UIKit

// MARK: - Activity

final class FireProfileActivityTableCell: UITableViewCell {
    static let reuseID = "FireProfileActivityTableCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        textLabel?.numberOfLines = 2
        textLabel?.textColor = FireTheme.uiInk
        detailTextLabel?.textColor = FireTheme.uiSubtleInk
        detailTextLabel?.numberOfLines = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(action: UserActionState) {
        let excerpt = action.excerpt.flatMap { FireProfileFormat.plainText(fromHTML: $0) }
        textLabel?.text = (excerpt?.isEmpty == false ? excerpt : nil)
            ?? action.title
            ?? "动态 #\(action.actionType)"
        detailTextLabel?.text = action.createdAt.map { FireProfileFormat.relativeTime($0) }
    }
}

enum FireProfileFormat {
    static func number(_ value: UInt32) -> String {
        if value >= 10_000 { return String(format: "%.1fw", Double(value) / 10_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    static func relativeTime(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: isoDate) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: isoDate)
        }()
        guard let date else { return isoDate }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    static func plainText(fromHTML rawHtml: String) -> String {
        guard let data = rawHtml.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              )
        else {
            return rawHtml
        }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
