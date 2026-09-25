import Combine
import SnapKit
import SwiftUI
import UIKit

@MainActor
extension FireProfileViewController {
    func applyGroupedChrome(to cell: UITableViewCell) {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = FireTheme.uiSurface
        background.cornerRadius = FireTheme.cornerRadius
        cell.backgroundConfiguration = background
        cell.tintColor = FireTheme.uiTertiaryInk
    }

    func configureMenuRow(
        _ cell: FireProfileMenuRowCell,
        systemImage: String,
        title: String,
        value: String? = nil,
        iconWellColor: UIColor
    ) {
        applyGroupedChrome(to: cell)
        cell.configure(
            systemImage: systemImage,
            title: title,
            value: value,
            iconWellColor: iconWellColor
        )
    }
}

extension FireProfileViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .error:
            return (profileViewModel.errorMessage ?? appViewModel.errorMessage) == nil ? 0 : 1
        case .header:
            return 1
        case .social:
            return SocialRow.allCases.count
        case .content:
            return ContentRow.allCases.count
        case .account:
            return AccountRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .social: return "社交"
        case .content: return "内容"
        case .account: return "账户"
        case .error, .header:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textLabel?.textColor = FireTheme.uiTertiaryInk
        header.textLabel?.text = header.textLabel?.text?.uppercased()
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .error, .header:
            return CGFloat.leastNormalMagnitude
        case .social, .content, .account:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard let section = Section(rawValue: section) else { return 6 }
        switch section {
        case .error:
            return CGFloat.leastNormalMagnitude
        case .header:
            return 4
        case .social, .content, .account:
            return 6
        }
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableView.automaticDimension
        }
        switch section {
        case .social, .content, .account:
            return FireProfileMenuRowCell.preferredHeight
        case .error, .header:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch section {
        case .error:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            applyGroupedChrome(to: cell)
            var content = cell.defaultContentConfiguration()
            content.text = profileViewModel.errorMessage ?? appViewModel.errorMessage
            content.textProperties.color = FireTheme.uiError
            content.textProperties.font = .preferredFont(forTextStyle: .footnote)
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            return cell
        case .header:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileHeaderTableCell.reuseID,
                for: indexPath
            ) as! FireProfileHeaderTableCell
            cell.configure(
                displayName: displayName,
                username: displayUsername,
                avatarTemplate: profileViewModel.profile?.avatarTemplate,
                bio: profileViewModel.profile?.bioPlainText,
                trustLevel: profileViewModel.profile?.trustLevel,
                followers: profileViewModel.profile?.totalFollowers ?? 0,
                likes: profileViewModel.summary?.stats.likesReceived ?? 0,
                following: profileViewModel.profile?.totalFollowing ?? 0
            )
            return cell
        case .social:
            let row = SocialRow.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileMenuRowCell.reuseID,
                for: indexPath
            ) as! FireProfileMenuRowCell
            configureMenuRow(
                cell,
                systemImage: row.systemImage,
                title: row.title,
                value: value(for: row),
                iconWellColor: row.iconWellColor
            )
            return cell
        case .content:
            let row = ContentRow.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileMenuRowCell.reuseID,
                for: indexPath
            ) as! FireProfileMenuRowCell
            configureMenuRow(
                cell,
                systemImage: row.systemImage,
                title: row.title,
                value: value(for: row),
                iconWellColor: row.iconWellColor
            )
            return cell
        case .account:
            let row = AccountRow.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: FireProfileMenuRowCell.reuseID,
                for: indexPath
            ) as! FireProfileMenuRowCell
            configureMenuRow(
                cell,
                systemImage: row.systemImage,
                title: row.title,
                iconWellColor: row.iconWellColor
            )
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .error, .header:
            break
        case .social:
            openSocial(SocialRow.allCases[indexPath.row])
        case .content:
            openContent(ContentRow.allCases[indexPath.row])
        case .account:
            openAccount(AccountRow.allCases[indexPath.row])
        }
    }
}
